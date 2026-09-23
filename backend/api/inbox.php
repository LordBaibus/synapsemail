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
    $stmt = $conn->prepare(
        'SELECT id, sender_email, recipient_email, subject, body, is_read, thread_id, reply_to_id, created_at
         FROM emails
         WHERE sender_email = ? AND deleted_by_sender = 0
         ORDER BY created_at DESC'
    );
    $stmt->bind_param('s', $user['email']);
} else {
    $stmt = $conn->prepare(
        'SELECT id, sender_email, recipient_email, subject, body, is_read, thread_id, reply_to_id, created_at
         FROM emails
         WHERE recipient_email = ? AND deleted_by_recipient = 0
         ORDER BY created_at DESC'
    );
    $stmt->bind_param('s', $user['email']);
}

$stmt->execute();
$result = $stmt->get_result();

$emails = [];
while ($row = $result->fetch_assoc()) {
    $row['id'] = (int) $row['id'];
    $row['is_read'] = (bool) $row['is_read'];
    $row['thread_id'] = $row['thread_id'] !== null ? (int) $row['thread_id'] : null;
    $row['reply_to_id'] = $row['reply_to_id'] !== null ? (int) $row['reply_to_id'] : null;
    $emails[] = $row;
}

respond(true, '', ['emails' => $emails]);
