<?php
/**
 * Streams one attachment's file bytes back to the caller (for viewing or
 * downloading an image/file from a message), after confirming the current
 * user was a sender or recipient of the email it belongs to.
 *
 * GET attachment.php?id=<attachment id>
 * Auth via the same Bearer token as every other endpoint - but since this
 * returns raw file bytes (not JSON), errors are also plain text/JSON with
 * a non-200 status rather than the usual respond() JSON envelope, so a
 * failed request doesn't get treated as a valid file.
 */
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../config/helpers.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type, Authorization');
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405);
    exit('Method not allowed');
}

header('Access-Control-Allow-Origin: *');

$conn = getDbConnection();
$user = requireAuth($conn);

$attachmentId = (int) ($_GET['id'] ?? 0);
if ($attachmentId <= 0) {
    http_response_code(400);
    exit('Missing or invalid id');
}

$stmt = $conn->prepare(
    'SELECT a.original_name, a.stored_name, a.mime_type, a.email_id, e.sender_email, e.recipient_email
     FROM attachments a
     JOIN emails e ON e.id = a.email_id
     WHERE a.id = ?
     LIMIT 1'
);
$stmt->bind_param('i', $attachmentId);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows === 0) {
    http_response_code(404);
    exit('Attachment not found');
}

$row = $result->fetch_assoc();
$isParticipant = $row['sender_email'] === $user['email'] || $row['recipient_email'] === $user['email'];
if (!$isParticipant) {
    http_response_code(403);
    exit('Forbidden');
}

$path = __DIR__ . '/../uploads/' . $row['email_id'] . '/' . $row['stored_name'];
if (!is_file($path)) {
    http_response_code(404);
    exit('File no longer available');
}

header('Content-Type: ' . $row['mime_type']);
header('Content-Length: ' . filesize($path));
header('Content-Disposition: inline; filename="' . str_replace('"', '', $row['original_name']) . '"');
header('Cache-Control: private, max-age=3600');
readfile($path);
