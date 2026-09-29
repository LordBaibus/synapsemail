<?php
/**
 * Returns the logged-in user's inbox (received) or sent folder,
 * depending on ?folder=inbox|sent (default inbox).
 */
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../config/helpers.php';

sendJsonHeaders();

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    respond(false, 'Method not allowed', [], 405);
}

$conn = getDbConnection();
$user = requireAuth($conn);

$folder = $_GET['folder'] ?? 'inbox';

if ($folder === 'sent') {
    // Sent shows everything the user sent, including still-pending
    // scheduled sends and ones that failed to deliver - so they can see
    // and manage them (status field tells the UI which is which).
    $stmt = $conn->prepare(
        'SELECT id, sender_email, recipient_email, cc, bcc, subject, body, is_read, thread_id, reply_to_id, scheduled_at, status, created_at
         FROM emails
         WHERE sender_email = ? AND deleted_by_sender = 0
         ORDER BY created_at DESC'
    );
    $stmt->bind_param('s', $user['email']);
} else {
    // Inbox only shows mail that has actually been delivered - a
    // scheduled email the user hasn't received yet must not show up here.
    $stmt = $conn->prepare(
        "SELECT id, sender_email, recipient_email, cc, bcc, subject, body, is_read, thread_id, reply_to_id, scheduled_at, status, created_at
         FROM emails
         WHERE recipient_email = ? AND deleted_by_recipient = 0 AND status != 'scheduled'
         ORDER BY created_at DESC"
    );
    $stmt->bind_param('s', $user['email']);
}

$stmt->execute();
$result = $stmt->get_result();

$emails = [];
$ids = [];
while ($row = $result->fetch_assoc()) {
    $row['id'] = (int) $row['id'];
    $row['is_read'] = (bool) $row['is_read'];
    $row['thread_id'] = $row['thread_id'] !== null ? (int) $row['thread_id'] : null;
    $row['reply_to_id'] = $row['reply_to_id'] !== null ? (int) $row['reply_to_id'] : null;
    $row['attachments'] = [];
    $emails[] = $row;
    $ids[] = $row['id'];
}

// One extra query for all attachment rows across this whole list, instead
// of one query per email - cheap either way at this scale, but avoids N+1.
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
    foreach ($emails as &$e) {
        $e['attachments'] = $byEmailId[$e['id']] ?? [];
    }
    unset($e);
}

respond(true, '', ['emails' => $emails]);
