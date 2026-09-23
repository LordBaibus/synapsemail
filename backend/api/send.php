<?php
/**
 * Sends an email: stores it in the `emails` table (so the recipient sees it
 * in-app if they're also a user of this system) AND delivers it via real
 * SMTP, so it also reaches any real inbox. Optionally attaches to a thread
 * when `reply_to_id` is given.
 */
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../config/helpers.php';

sendJsonHeaders();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond(false, 'Method not allowed', [], 405);
}

$conn = getDbConnection();
$user = requireAuth($conn);

$body = getJsonBody();
$recipient = trim(strtolower($body['recipient_email'] ?? ''));
$subject = trim($body['subject'] ?? '(no subject)');
$message = trim($body['body'] ?? '');
$replyToId = isset($body['reply_to_id']) ? (int) $body['reply_to_id'] : 0;

if ($recipient === '' || $message === '') {
    respond(false, 'recipient_email and body are required', [], 400);
}

if (!filter_var($recipient, FILTER_VALIDATE_EMAIL)) {
    respond(false, 'Invalid recipient email address', [], 400);
}

// If this is a reply, resolve the thread it belongs to (the original
// message's own thread_id if it already has one, otherwise the original
// message's own id becomes the thread root) and confirm the user was
// actually a participant in that original message before attaching to it.
$threadId = null;
if ($replyToId > 0) {
    $stmt = $conn->prepare(
        'SELECT id, thread_id, sender_email, recipient_email FROM emails WHERE id = ? LIMIT 1'
    );
    $stmt->bind_param('i', $replyToId);
    $stmt->execute();
    $result = $stmt->get_result();

    if ($result->num_rows === 0) {
        respond(false, 'The message you are replying to no longer exists', [], 404);
    }

    $original = $result->fetch_assoc();
    $isParticipant = $original['sender_email'] === $user['email'] || $original['recipient_email'] === $user['email'];
    if (!$isParticipant) {
        respond(false, 'You cannot reply to this message', [], 403);
    }

    $threadId = $original['thread_id'] !== null ? (int) $original['thread_id'] : (int) $original['id'];
}

$replyToIdOrNull = $replyToId > 0 ? $replyToId : null;

// 1. Store in our own database so the in-app inbox shows it (CRUD "Create").
$stmt = $conn->prepare(
    'INSERT INTO emails (sender_email, recipient_email, subject, body, thread_id, reply_to_id) VALUES (?, ?, ?, ?, ?, ?)'
);
$stmt->bind_param('ssssii', $user['email'], $recipient, $subject, $message, $threadId, $replyToIdOrNull);

if (!$stmt->execute()) {
    respond(false, 'Failed to save the email', [], 500);
}

$emailId = $stmt->insert_id;

// A freshly-created thread's root should point at itself so every message
// in the thread (including the first) carries a usable thread_id.
if ($threadId === null) {
    $update = $conn->prepare('UPDATE emails SET thread_id = ? WHERE id = ?');
    $update->bind_param('ii', $emailId, $emailId);
    $update->execute();
}

// 2. Actually deliver it via SMTP, so it also reaches real inboxes
//    (e.g. Gmail, Outlook) outside this app.
$mailSent = sendMailNotification($recipient, $user['full_name'], $user['email'], $subject, $message);

respond(true, $mailSent ? 'Email sent' : 'Email saved, but delivery to the recipient\'s inbox failed', [
    'id' => $emailId,
    'mail_delivered' => $mailSent,
    'mail_error' => $mailSent ? null : lastMailError(),
]);
