<?php
/**
 * One-off maintenance script: re-detects the real MIME type of every
 * already-stored attachment (from its actual file bytes, via
 * detectMimeType() in config/helpers.php) and corrects the `attachments`
 * table wherever it's wrong.
 *
 * Why this is needed: every attachment sent before the send.php/helpers.php
 * fix was stored with mime_type = "application/octet-stream", because the
 * Flutter app's upload request never set a real Content-Type on the file
 * part and the backend used to trust that blindly. That made every photo
 * misclassified as a generic file client-side (EmailAttachment.isImage
 * checks mimeType.startsWith('image/')), so it rendered as a file chip
 * instead of an image thumbnail. New uploads are fixed automatically by
 * saveUploadedAttachments() now detecting the real type from file bytes -
 * this script corrects the rows that were already saved before that fix
 * shipped.
 *
 * CLI-only (never runs over HTTP, even if this file is web-reachable) -
 * run it once via SSH:
 *   php backend/scripts/backfill_attachment_mime_types.php
 */
if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    exit("This script is CLI-only.\n");
}

require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../config/helpers.php';

$conn = getDbConnection();

$result = $conn->query('SELECT id, email_id, stored_name, mime_type FROM attachments ORDER BY id ASC');

$checked = 0;
$fixed = 0;
$missingFile = 0;

while ($row = $result->fetch_assoc()) {
    $checked++;
    $path = attachmentsDir((int) $row['email_id']) . '/' . $row['stored_name'];

    if (!is_file($path)) {
        $missingFile++;
        echo "  [skip] attachment #{$row['id']}: file not found on disk ({$path})\n";
        continue;
    }

    $detected = detectMimeType($path, '');

    if ($detected !== $row['mime_type']) {
        $update = $conn->prepare('UPDATE attachments SET mime_type = ? WHERE id = ?');
        $update->bind_param('si', $detected, $row['id']);
        $update->execute();
        $fixed++;
        echo "  [fixed] attachment #{$row['id']}: '{$row['mime_type']}' -> '{$detected}'\n";
    }
}

echo "\nDone. Checked {$checked}, fixed {$fixed}, missing files {$missingFile}.\n";
