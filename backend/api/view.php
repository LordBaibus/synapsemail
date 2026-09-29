<?php
/**
 * Fetch a single email by id (CRUD "Read" - single record) and mark it
 * read if the current user is the recipient.
 */
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../config/helpers.php';

sendJsonHeaders();

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    respond(false, 'Method not allowed', [], 405);
}

$conn = getDbConnection();
$user = requireAuth($conn);

$id = (int) ($_GET['id'] ?? 0);
if ($id <= 0) {
    respond(false, 'Missing or invalid id', [], 400);
}

$stmt = $conn->prepare(
    'SELECT id, sender_email, recipient_email, cc, bcc, subject, body, is_read, thread_id, reply_to_id, scheduled_at, status, created_at
     FROM emails
     WHERE id = ? AND (sender_email = ? OR recipient_email = ?)
     LIMIT 1'
);
$stmt->bind_param('iss', $id, $user['email'], $user['email']);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows === 0) {
    respond(false, 'Email not found', [], 404);
}

$email = $result->fetch_assoc();

// Mark as read if the requester is the recipient.
if ($email['recipient_email'] === $user['email'] && !$email['is_read']) {
    $update = $conn->prepare('UPDATE emails SET is_read = 1 WHERE id = ?');
    $update->bind_param('i', $id);
    $update->execute();
    $email['is_read'] = 1;
}

$email['id'] = (int) $email['id'];
$email['is_read'] = (bool) $email['is_read'];
$email['thread_id'] = $email['thread_id'] !== null ? (int) $email['thread_id'] : null;
$email['reply_to_id'] = $email['reply_to_id'] !== null ? (int) $email['reply_to_id'] : null;
$email['attachments'] = fetchAttachments($conn, $email['id']);

// If this message is a reply, include a compact snapshot of the message it
// replied to, so the client can show it inline (Messenger-style) without a
// second round trip.
$repliedTo = null;
if ($email['reply_to_id'] !== null) {
    $origStmt = $conn->prepare(
        'SELECT id, sender_email, recipient_email, subject, body, created_at
         FROM emails
         WHERE id = ? AND (sender_email = ? OR recipient_email = ?)
         LIMIT 1'
    );
    $origStmt->bind_param('iss', $email['reply_to_id'], $user['email'], $user['email']);
    $origStmt->execute();
    $origResult = $origStmt->get_result();
    if ($origResult->num_rows > 0) {
        $repliedTo = $origResult->fetch_assoc();
        $repliedTo['id'] = (int) $repliedTo['id'];
    }
}

respond(true, '', ['email' => $email, 'replied_to' => $repliedTo]);
