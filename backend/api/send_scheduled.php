<?php
/**
 * Cron-only script: finds every email whose scheduled_at has passed and
 * status is still 'scheduled', delivers it via SMTP, and flips its status
 * to 'sent' (or 'failed' if delivery fails - it stays in Sent either way,
 * matching how a normal failed send behaves).
 *
 * Not part of the public api/ folder's request/response contract (no auth
 * token, no JSON POST body) - it's meant to be invoked by a Hostinger
 * cron job, not the Flutter app. To set it up:
 *
 *   1. hPanel > Advanced > Cron Jobs > Create a new cron job
 *   2. Command: php /home/<your-user>/domains/synapsemail.site/public_html/backend/api/send_scheduled.php
 *      (adjust the path to match where this file actually lives on your
 *      Hostinger account - check hPanel > File Manager for the exact path)
 *   3. Run every 1-5 minutes (Hostinger's cron UI has a preset for this,
 *      or use the custom schedule "*\/5 * * * *" for every 5 minutes)
 *
 * Can also be run manually for testing: php send_scheduled.php
 */
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../config/helpers.php';

// This script is only ever run from the command line (cron) or, for
// manual testing, directly in a browser by whoever controls the server -
// never called by the Flutter app - so there's no bearer-token auth here.
// As a safety net against it being hit by a stray public request, refuse
// anything that looks like a normal web request with query params.
if (php_sapi_name() !== 'cli' && !empty($_GET) && empty($_GET['manual_run'])) {
    http_response_code(403);
    exit('Forbidden');
}

$conn = getDbConnection();

$stmt = $conn->prepare(
    "SELECT id, sender_email, recipient_email, cc, bcc, subject, body
     FROM emails
     WHERE status = 'scheduled' AND scheduled_at <= NOW()
     ORDER BY scheduled_at ASC
     LIMIT 20"
);
$stmt->execute();
$result = $stmt->get_result();

$due = [];
while ($row = $result->fetch_assoc()) {
    $due[] = $row;
}

if (empty($due)) {
    echo "No scheduled emails due.\n";
    exit;
}

foreach ($due as $email) {
    $emailId = (int) $email['id'];

    // Look up the sender's display name (not stored on the emails row
    // itself).
    $userStmt = $conn->prepare('SELECT full_name FROM users WHERE email = ? LIMIT 1');
    $userStmt->bind_param('s', $email['sender_email']);
    $userStmt->execute();
    $userResult = $userStmt->get_result();
    $senderName = $userResult->num_rows > 0
        ? $userResult->fetch_assoc()['full_name']
        : $email['sender_email'];

    $ccList = $email['cc'] !== null ? array_map('trim', explode(',', $email['cc'])) : [];
    $bccList = $email['bcc'] !== null ? array_map('trim', explode(',', $email['bcc'])) : [];
    $attachmentPaths = attachmentFilePaths($conn, $emailId);

    $mailSent = sendMailNotification(
        $email['recipient_email'],
        $senderName,
        $email['sender_email'],
        $email['subject'],
        $email['body'],
        $ccList,
        $bccList,
        $attachmentPaths
    );

    $newStatus = $mailSent ? 'sent' : 'failed';
    $update = $conn->prepare('UPDATE emails SET status = ? WHERE id = ?');
    $update->bind_param('si', $newStatus, $emailId);
    $update->execute();

    echo "Email #{$emailId}: " . ($mailSent ? 'sent' : 'FAILED (' . lastMailError() . ')') . "\n";
}
