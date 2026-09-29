<?php
/**
 * Sends an email: stores it in the `emails` table (so the recipient sees it
 * in-app if they're also a user of this system) AND delivers it via real
 * SMTP, so it also reaches any real inbox. Optionally attaches to a thread
 * when `reply_to_id` is given.
 *
 * Unlike the other endpoints, this one is multipart/form-data (not JSON) -
 * required so it can also carry attachment file uploads. Regular fields
 * arrive in $_POST instead of a JSON body:
 *   recipient_email, subject, body, reply_to_id (optional),
 *   cc, bcc (optional, comma/semicolon-separated address lists),
 *   scheduled_at (optional, "YYYY-MM-DD HH:MM:SS" - if set and in the
 *     future, the email is stored but NOT delivered yet; the
 *     send_scheduled.php cron script delivers it later)
 * Files arrive as attachments[] (repeat the field name once per file).
 */
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../config/helpers.php';

sendJsonHeaders();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond(false, 'Method not allowed', [], 405);
}

$conn = getDbConnection();
$user = requireAuth($conn);

$recipient = trim(strtolower($_POST['recipient_email'] ?? ''));
$subject = trim($_POST['subject'] ?? '(no subject)');
$message = trim($_POST['body'] ?? '');
$replyToId = isset($_POST['reply_to_id']) ? (int) $_POST['reply_to_id'] : 0;
$scheduledAtRaw = trim($_POST['scheduled_at'] ?? '');

if ($recipient === '' || $message === '') {
    respond(false, 'recipient_email and body are required', [], 400);
}

if (!filter_var($recipient, FILTER_VALIDATE_EMAIL)) {
    respond(false, 'Invalid recipient email address', [], 400);
}

try {
    $ccList = parseAddressList($_POST['cc'] ?? null);
    $bccList = parseAddressList($_POST['bcc'] ?? null);
} catch (RuntimeException $e) {
    respond(false, $e->getMessage(), [], 400);
}

// Scheduled send: must be a valid, future timestamp. Anything in the past
// (or unparsable) is treated as "send now" rather than silently failing.
$scheduledAt = null;
$status = 'sent';
if ($scheduledAtRaw !== '') {
    $parsed = DateTime::createFromFormat('Y-m-d H:i:s', $scheduledAtRaw);
    if ($parsed !== false && $parsed->getTimestamp() > time()) {
        $scheduledAt = $parsed->format('Y-m-d H:i:s');
        $status = 'scheduled';
    }
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
$ccStored = !empty($ccList) ? implode(', ', $ccList) : null;
$bccStored = !empty($bccList) ? implode(', ', $bccList) : null;

// 1. Store in our own database so the in-app inbox shows it (CRUD "Create").
$stmt = $conn->prepare(
    'INSERT INTO emails (sender_email, recipient_email, cc, bcc, subject, body, thread_id, reply_to_id, scheduled_at, status)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
);
$stmt->bind_param(
    'ssssssiiss',
    $user['email'], $recipient, $ccStored, $bccStored, $subject, $message,
    $threadId, $replyToIdOrNull, $scheduledAt, $status
);

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

// 2. Save any attached files to disk (regardless of whether this is a
//    scheduled send - they need to exist already so the cron script can
//    attach them later).
try {
    $savedAttachments = saveUploadedAttachments($conn, $emailId);
} catch (RuntimeException $e) {
    // Roll back the email row rather than leaving a half-sent message with
    // no attachments the user thought they attached.
    $del = $conn->prepare('DELETE FROM emails WHERE id = ?');
    $del->bind_param('i', $emailId);
    $del->execute();
    deleteAttachmentFiles($emailId);
    respond(false, $e->getMessage(), [], 400);
}

// 3. If this is a scheduled send, stop here - send_scheduled.php delivers
//    it later. Otherwise deliver immediately via SMTP right now.
if ($status === 'scheduled') {
    respond(true, 'Email scheduled', [
        'id' => $emailId,
        'status' => 'scheduled',
        'scheduled_at' => $scheduledAt,
        'attachments' => $savedAttachments,
    ]);
}

$attachmentPaths = attachmentFilePaths($conn, $emailId);

$mailSent = sendMailNotification(
    $recipient,
    $user['full_name'],
    $user['email'],
    $subject,
    $message,
    $ccList,
    $bccList,
    $attachmentPaths
);

if (!$mailSent) {
    $conn->query('UPDATE emails SET status = \'failed\' WHERE id = ' . (int) $emailId);
}

respond(true, $mailSent ? 'Email sent' : 'Email saved, but delivery to the recipient\'s inbox failed', [
    'id' => $emailId,
    'mail_delivered' => $mailSent,
    'mail_error' => $mailSent ? null : lastMailError(),
    'attachments' => $savedAttachments,
]);
