<?php
/**
 * Returns every message that belongs to the same conversation as the given
 * email id, ordered oldest-first, so the app can render a full Messenger-
 * style thread instead of just one message plus its immediate parent.
 *
 * A message's thread is identified by its thread_id (the root message's
 * own id). A message with no thread_id (pre-threading data, or a message
 * that was never replied to) is treated as a thread of one: itself.
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

// Resolve the thread root: the given message's own thread_id if it has
// one, otherwise its own id.
$stmt = $conn->prepare(
    'SELECT id, thread_id, sender_email, recipient_email
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

$anchor = $result->fetch_assoc();
$threadId = $anchor['thread_id'] !== null ? (int) $anchor['thread_id'] : (int) $anchor['id'];

// Every message sharing that thread_id (or, for the root itself when older
// rows never got a thread_id backfilled, matching the root's own id) that
// this user was a participant in.
$stmt = $conn->prepare(
    "SELECT id, sender_email, recipient_email, cc, bcc, subject, body, is_read, thread_id, reply_to_id, scheduled_at, status, created_at
     FROM emails
     WHERE (thread_id = ? OR id = ?) AND (sender_email = ? OR recipient_email = ?)
       AND NOT (status = 'scheduled' AND recipient_email = ?)
     ORDER BY created_at ASC, id ASC"
);
$stmt->bind_param('iisss', $threadId, $threadId, $user['email'], $user['email'], $user['email']);
$stmt->execute();
$result = $stmt->get_result();

$messages = [];
$unreadIds = [];
$ids = [];
while ($row = $result->fetch_assoc()) {
    $row['id'] = (int) $row['id'];
    $row['is_read'] = (bool) $row['is_read'];
    $row['thread_id'] = $row['thread_id'] !== null ? (int) $row['thread_id'] : null;
    $row['reply_to_id'] = $row['reply_to_id'] !== null ? (int) $row['reply_to_id'] : null;
    $messages[] = $row;
    $ids[] = $row['id'];

    if ($row['recipient_email'] === $user['email'] && !$row['is_read']) {
        $unreadIds[] = $row['id'];
    }
}

// Attach each message's attachment list in one extra query.
if (!empty($ids)) {
    $placeholders = implode(',', array_fill(0, count($ids), '?'));
    $types = str_repeat('i', count($ids));
    $attStmt = $conn->prepare(
        "SELECT id, email_id, original_name, mime_type, size_bytes FROM attachments WHERE email_id IN ($placeholders) ORDER BY id ASC"
    );
    $attStmt->bind_param($types, ...$ids);
    $attStmt->execute();
    $attResult = $attStmt->get_result();
    $byEmailId = [];
    while ($att = $attResult->fetch_assoc()) {
        $att['id'] = (int) $att['id'];
        $att['size_bytes'] = (int) $att['size_bytes'];
        $emailId = (int) $att['email_id'];
        unset($att['email_id']);
        $byEmailId[$emailId][] = $att;
    }
    foreach ($messages as &$m) {
        $m['attachments'] = $byEmailId[$m['id']] ?? [];
    }
    unset($m);
}

// Mark every unread message the user received in this thread as read,
// same as opening a single message does.
if (!empty($unreadIds)) {
    $placeholders = implode(',', array_fill(0, count($unreadIds), '?'));
    $types = str_repeat('i', count($unreadIds));
    $update = $conn->prepare("UPDATE emails SET is_read = 1 WHERE id IN ($placeholders)");
    $update->bind_param($types, ...$unreadIds);
    $update->execute();
    foreach ($messages as &$m) {
        if (in_array($m['id'], $unreadIds, true)) {
            $m['is_read'] = true;
        }
    }
    unset($m);
}

respond(true, '', ['messages' => $messages, 'thread_id' => $threadId]);
