<?php
/**
 * Streams one attachment's file bytes back to the caller (for viewing or
 * downloading an image/file from a message), after confirming the current
 * user was a sender or recipient of the email it belongs to.
 *
 * GET attachment.php?id=<attachment id>&token=<optional, see below>
 * Auth via the same Bearer token as every other endpoint when the caller
 * can send one (the in-app image thumbnails do) - but since this returns
 * raw file bytes (not JSON), errors are also plain text/JSON with a
 * non-200 status rather than the usual respond() JSON envelope, so a
 * failed request doesn't get treated as a valid file.
 *
 * Also accepts the token as ?token=<token> (via requireAuthFromRequest)
 * for the two call sites that hand this URL to something outside our own
 * HTTP client and can't attach a header: opening a non-image file in the
 * device's own viewer (url_launcher, LaunchMode.externalApplication), and
 * any platform image loader that doesn't support custom headers.
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
$user = requireAuthFromRequest($conn);

$attachmentId = (int) ($_GET['id'] ?? 0);
if ($attachmentId <= 0) {
    http_response_code(400);
    exit('Missing or invalid id');
}

$stmt = $conn->prepare(
    'SELECT a.original_name, a.stored_name, a.mime_type, a.email_id,
            e.sender_email, e.recipient_email, e.cc, e.bcc
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

// Cc/Bcc are stored as comma-separated strings (see EmailMessage._splitAddresses
// on the Flutter side) - a Cc'd or Bcc'd participant (or an extra "To"
// recipient, which rides along as Cc - see compose_screen.dart's _send())
// is just as entitled to view the attachment as the sender/primary
// recipient, but was previously getting a 403 here.
$ccList = array_map('trim', explode(',', (string) ($row['cc'] ?? '')));
$bccList = array_map('trim', explode(',', (string) ($row['bcc'] ?? '')));
$isParticipant = in_array($user['email'], [$row['sender_email'], $row['recipient_email'], ...$ccList, ...$bccList], true);
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
