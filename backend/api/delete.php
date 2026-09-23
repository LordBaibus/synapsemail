<?php
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../config/helpers.php';

sendJsonHeaders();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond(false, 'Method not allowed', [], 405);
}

$conn = getDbConnection();
$user = requireAuth($conn);

$body = getJsonBody();
$id = (int) ($body['id'] ?? 0);

if ($id <= 0) {
    respond(false, 'Missing or invalid id', [], 400);
}

$stmt = $conn->prepare('SELECT sender_email, recipient_email FROM emails WHERE id = ? LIMIT 1');
$stmt->bind_param('i', $id);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows === 0) {
    respond(false, 'Email not found', [], 404);
}

$email = $result->fetch_assoc();
$isSender = $email['sender_email'] === $user['email'];
$isRecipient = $email['recipient_email'] === $user['email'];

if (!$isSender && !$isRecipient) {
    respond(false, 'You do not have permission to delete this email', [], 403);
}

if ($isSender) {
    $stmt = $conn->prepare('UPDATE emails SET deleted_by_sender = 1 WHERE id = ?');
    $stmt->bind_param('i', $id);
    $stmt->execute();
}
if ($isRecipient) {
    $stmt = $conn->prepare('UPDATE emails SET deleted_by_recipient = 1 WHERE id = ?');
    $stmt->bind_param('i', $id);
    $stmt->execute();
}
$stmt = $conn->prepare(
    'DELETE FROM emails WHERE id = ? AND deleted_by_sender = 1 AND deleted_by_recipient = 1'
);
$stmt->bind_param('i', $id);
$stmt->execute();

respond(true, 'Email deleted');
