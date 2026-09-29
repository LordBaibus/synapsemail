<?php
/**
 * Shared helpers: CORS/JSON headers, auth token check, input parsing.
 */

require_once __DIR__ . '/../lib/PHPMailer/Exception.php';
require_once __DIR__ . '/../lib/PHPMailer/PHPMailer.php';
require_once __DIR__ . '/../lib/PHPMailer/SMTP.php';

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception as PHPMailerException;

function sendJsonHeaders(): void {
    header('Content-Type: application/json; charset=utf-8');
    // Restrict this to your app's actual origin(s) in production if serving a web build.
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type, Authorization');

    if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
        http_response_code(200);
        exit;
    }
}

function getJsonBody(): array {
    $raw = file_get_contents('php://input');
    $data = json_decode($raw, true);
    return is_array($data) ? $data : [];
}

function respond(bool $success, string $message = '', array $extra = [], int $code = 200): void {
    http_response_code($code);
    echo json_encode(array_merge(['success' => $success, 'message' => $message], $extra));
    exit;
}

/**
 * Very simple bearer-token auth. On login we issue a random token stored
 * in the `users` table (auth_token column). The Flutter app stores this
 * token locally (shared_preferences) and sends it as:
 *   Authorization: Bearer <token>
 * on every request. This is intentionally simple for a school-project
 * scale system — for production use something like JWT with expiry.
 */
function requireAuth(mysqli $conn): array {
    $headers = getallheaders();
    $authHeader = $headers['Authorization'] ?? $headers['authorization'] ?? '';

    if (!preg_match('/Bearer\s+(.+)/i', $authHeader, $matches)) {
        respond(false, 'Missing or invalid Authorization header', [], 401);
    }

    $token = $matches[1];
    $stmt = $conn->prepare('SELECT id, full_name, email FROM users WHERE auth_token = ? LIMIT 1');
    $stmt->bind_param('s', $token);
    $stmt->execute();
    $result = $stmt->get_result();

    if ($result->num_rows === 0) {
        respond(false, 'Invalid or expired session, please log in again', [], 401);
    }

    return $result->fetch_assoc();
}

function generateToken(): string {
    return bin2hex(random_bytes(32));
}

/**
 * Same check as requireAuth(), but also accepts the token as a `?token=`
 * query parameter when no Authorization header is present.
 *
 * Only attachment.php uses this. Everywhere else the app can always attach
 * a real Authorization header (it controls the HTTP request), but two
 * attachment-viewing paths hand the URL to something that doesn't support
 * custom headers - Image.network's <img>-like network image loader on some
 * platforms, and url_launcher's LaunchMode.externalApplication, which opens
 * the link in the device's own browser/PDF viewer/etc. as a plain URL with
 * no way to inject a header. A query-token is the standard way to
 * authenticate a "hand this link to another app" request (the same pattern
 * S3 presigned URLs, Google Drive share links, etc. use).
 */
function requireAuthFromRequest(mysqli $conn): array {
    $headers = getallheaders();
    $authHeader = $headers['Authorization'] ?? $headers['authorization'] ?? '';

    if (preg_match('/Bearer\s+(.+)/i', $authHeader, $matches)) {
        $token = $matches[1];
    } else {
        $token = trim((string) ($_GET['token'] ?? ''));
    }

    if ($token === '') {
        respond(false, 'Missing or invalid Authorization header', [], 401);
    }

    $stmt = $conn->prepare('SELECT id, full_name, email FROM users WHERE auth_token = ? LIMIT 1');
    $stmt->bind_param('s', $token);
    $stmt->execute();
    $result = $stmt->get_result();

    if ($result->num_rows === 0) {
        respond(false, 'Invalid or expired session, please log in again', [], 401);
    }

    return $result->fetch_assoc();
}

// ============================================================
// Attachments
// ============================================================

/** Max total size of all attachments on one email, in bytes (30MB). */
const MAX_ATTACHMENTS_BYTES = 30 * 1024 * 1024;

/**
 * Directory attachment files for a given email id are stored under.
 * Created on demand.
 */
function attachmentsDir(int $emailId): string {
    $dir = __DIR__ . '/../uploads/' . $emailId;
    if (!is_dir($dir)) {
        mkdir($dir, 0755, true);
    }
    return $dir;
}

/**
 * Determines a file's real MIME type by inspecting its actual bytes
 * (PHP's fileinfo extension), rather than trusting a client-supplied
 * Content-Type.
 *
 * This matters because the Flutter app's http package
 * (http.MultipartFile.fromBytes, used in ApiService.sendEmail) doesn't set
 * an explicit contentType on the uploaded file part, so it silently
 * defaults to "application/octet-stream" for every single attachment -
 * photos included. Trusting that client-reported value here meant every
 * photo ever sent was being stored with mime_type = "application/
 * octet-stream", which made EmailAttachment.isImage (mimeType.startsWith
 * ('image/')) always false on the Flutter side - so photos were always
 * rendered as a generic file chip instead of an image thumbnail, and
 * tapping one hit the exact same "open externally, unauthenticated" issue
 * that plain file attachments had.
 */
function detectMimeType(string $filePath, string $clientReportedType = ''): string {
    if (is_file($filePath) && function_exists('finfo_open')) {
        $finfo = finfo_open(FILEINFO_MIME_TYPE);
        if ($finfo !== false) {
            $detected = finfo_file($finfo, $filePath);
            finfo_close($finfo);
            if (is_string($detected) && $detected !== '') {
                return $detected;
            }
        }
    }
    return $clientReportedType !== '' ? $clientReportedType : 'application/octet-stream';
}

/**
 * Saves every uploaded file in $_FILES['attachments'] (a PHP multi-file
 * upload field, as sent by a Flutter http.MultipartRequest with several
 * files under the same field name) to disk under attachmentsDir($emailId)
 * and inserts one `attachments` row per file. Returns the list of saved
 * attachment rows, or throws a RuntimeException with a user-facing
 * message if the combined size exceeds MAX_ATTACHMENTS_BYTES or a file
 * fails to save.
 *
 * Safe to call with no files present (returns an empty array).
 */
function saveUploadedAttachments(mysqli $conn, int $emailId): array {
    if (empty($_FILES['attachments']) || empty($_FILES['attachments']['name'][0])) {
        return [];
    }

    $files = $_FILES['attachments'];
    $count = count($files['name']);

    $totalSize = 0;
    for ($i = 0; $i < $count; $i++) {
        if ($files['error'][$i] === UPLOAD_ERR_NO_FILE) continue;
        $totalSize += (int) $files['size'][$i];
    }
    if ($totalSize > MAX_ATTACHMENTS_BYTES) {
        $maxMb = (int) (MAX_ATTACHMENTS_BYTES / 1024 / 1024);
        throw new RuntimeException("Attachments are too large (max {$maxMb}MB total)");
    }

    $dir = attachmentsDir($emailId);
    $saved = [];

    for ($i = 0; $i < $count; $i++) {
        if ($files['error'][$i] === UPLOAD_ERR_NO_FILE) continue;
        if ($files['error'][$i] !== UPLOAD_ERR_OK) {
            throw new RuntimeException('One of the attachments failed to upload');
        }

        $originalName = basename($files['name'][$i]);
        $ext = pathinfo($originalName, PATHINFO_EXTENSION);
        $storedName = bin2hex(random_bytes(16)) . ($ext !== '' ? ".{$ext}" : '');
        $destination = "{$dir}/{$storedName}";

        if (!move_uploaded_file($files['tmp_name'][$i], $destination)) {
            throw new RuntimeException("Failed to save attachment \"{$originalName}\"");
        }

        // Detected from the file's actual bytes, not the client-reported
        // type - see detectMimeType()'s docblock for why that matters.
        $mimeType = detectMimeType($destination, $files['type'][$i] ?? '');
        $sizeBytes = (int) $files['size'][$i];

        $stmt = $conn->prepare(
            'INSERT INTO attachments (email_id, original_name, stored_name, mime_type, size_bytes) VALUES (?, ?, ?, ?, ?)'
        );
        $stmt->bind_param('isssi', $emailId, $originalName, $storedName, $mimeType, $sizeBytes);
        $stmt->execute();

        $saved[] = [
            'id' => $stmt->insert_id,
            'original_name' => $originalName,
            'mime_type' => $mimeType,
            'size_bytes' => $sizeBytes,
        ];
    }

    return $saved;
}

/**
 * Resolves the absolute on-disk path for every attachment on one email,
 * for passing to PHPMailer's addAttachment(). Returns a list of
 * ['path' => string, 'original_name' => string] pairs; any row whose file
 * is missing on disk is silently skipped (best-effort delivery).
 */
function attachmentFilePaths(mysqli $conn, int $emailId): array {
    $stmt = $conn->prepare(
        'SELECT original_name, stored_name FROM attachments WHERE email_id = ? ORDER BY id ASC'
    );
    $stmt->bind_param('i', $emailId);
    $stmt->execute();
    $result = $stmt->get_result();

    $dir = __DIR__ . '/../uploads/' . $emailId;
    $paths = [];
    while ($row = $result->fetch_assoc()) {
        $path = "{$dir}/{$row['stored_name']}";
        if (is_file($path)) {
            $paths[] = ['path' => $path, 'original_name' => $row['original_name']];
        }
    }
    return $paths;
}

/** Fetches the attachment rows for one email, for API responses. */
function fetchAttachments(mysqli $conn, int $emailId): array {
    $stmt = $conn->prepare(
        'SELECT id, original_name, mime_type, size_bytes FROM attachments WHERE email_id = ? ORDER BY id ASC'
    );
    $stmt->bind_param('i', $emailId);
    $stmt->execute();
    $result = $stmt->get_result();

    $rows = [];
    while ($row = $result->fetch_assoc()) {
        $row['id'] = (int) $row['id'];
        $row['size_bytes'] = (int) $row['size_bytes'];
        $rows[] = $row;
    }
    return $rows;
}

/** Deletes every file (and the containing directory) for one email's attachments. */
function deleteAttachmentFiles(int $emailId): void {
    $dir = __DIR__ . '/../uploads/' . $emailId;
    if (!is_dir($dir)) return;
    foreach (scandir($dir) as $file) {
        if ($file === '.' || $file === '..') continue;
        @unlink("{$dir}/{$file}");
    }
    @rmdir($dir);
}

/**
 * Splits a comma/semicolon-separated address list (as typed by the user
 * into a Cc/Bcc field, Gmail-style) into a clean array of valid, unique
 * email addresses. Throws RuntimeException if any entry isn't a valid
 * address.
 */
function parseAddressList(?string $raw): array {
    if ($raw === null || trim($raw) === '') return [];
    $parts = preg_split('/[,;]/', $raw) ?: [];
    $addresses = [];
    foreach ($parts as $part) {
        $address = strtolower(trim($part));
        if ($address === '') continue;
        if (!filter_var($address, FILTER_VALIDATE_EMAIL)) {
            throw new RuntimeException("\"{$address}\" is not a valid email address");
        }
        $addresses[$address] = true;
    }
    return array_keys($addresses);
}

/**
 * Generates a random 6-digit numeric OTP code (zero-padded, e.g. "004821").
 */
function generateOtpCode(): string {
    return str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);
}

/**
 * Holds the reason the most recent sendOtpEmail() call failed, if any.
 * Read this right after a false return to see what went wrong (also
 * written to the PHP error log either way).
 */
$GLOBALS['LAST_MAIL_ERROR'] = null;

function lastMailError(): ?string {
    return $GLOBALS['LAST_MAIL_ERROR'];
}

/**
 * Sends a 6-digit code to the given address via SMTP (PHPMailer), using
 * the real Hostinger mailbox configured in config/db.php. Raw PHP mail()
 * is not used because it is unreliable on shared hosting (often silently
 * dropped or caught by spam filters with no error reported).
 *
 * $intro is the sentence shown above the code, so this same function
 * serves both the registration OTP and the forgot-password OTP with
 * different wording.
 *
 * Returns true if the SMTP server accepted the message for delivery.
 */
function sendOtpEmail(string $toEmail, string $fullName, string $otpCode, string $subject = 'Your SynapseMail verification code', string $intro = 'Use the verification code below to finish creating your SynapseMail account. This code expires in 10 minutes.'): bool {
    $GLOBALS['LAST_MAIL_ERROR'] = null;
    $safeName = htmlspecialchars($fullName, ENT_QUOTES, 'UTF-8');
    $safeIntro = htmlspecialchars($intro, ENT_QUOTES, 'UTF-8');

    $htmlBody = '<!DOCTYPE html><html><body style="margin:0;padding:0;background-color:#0B0B12;font-family:Arial,Helvetica,sans-serif;">'
        . '<table width="100%" cellpadding="0" cellspacing="0" style="background-color:#0B0B12;padding:32px 0;"><tr><td align="center">'
        . '<table width="420" cellpadding="0" cellspacing="0" style="background-color:#15151f;border-radius:16px;padding:32px;">'
        . '<tr><td align="center" style="padding-bottom:16px;">'
        . '<span style="font-size:20px;font-weight:bold;color:#00E5FF;">Synapse</span>'
        . '<span style="font-size:20px;font-weight:bold;color:#6C5CE7;">Mail</span>'
        . '</td></tr>'
        . '<tr><td style="color:#ffffff;font-size:15px;line-height:1.5;">'
        . "Hi {$safeName},<br><br>{$safeIntro}"
        . '</td></tr>'
        . '<tr><td align="center" style="padding:28px 0;">'
        . "<span style=\"font-size:34px;font-weight:bold;letter-spacing:8px;color:#00E5FF;\">{$otpCode}</span>"
        . '</td></tr>'
        . '<tr><td style="color:#8a8a99;font-size:13px;line-height:1.5;">If you did not request this, you can safely ignore this email.</td></tr>'
        . '</table></td></tr></table></body></html>';

    $mail = new PHPMailer(true);
    try {
        $mail->isSMTP();
        $mail->Host = SMTP_HOST;
        $mail->SMTPAuth = true;
        $mail->Username = SMTP_USERNAME;
        $mail->Password = SMTP_PASSWORD;
        $mail->Port = SMTP_PORT;
        $mail->SMTPSecure = (SMTP_PORT === 465) ? 'ssl' : 'tls';
        $mail->CharSet = 'UTF-8';

        $mail->setFrom(SMTP_USERNAME, SMTP_FROM_NAME);
        $mail->addAddress($toEmail, $fullName);
        $mail->addReplyTo(SMTP_USERNAME, SMTP_FROM_NAME);

        $mail->isHTML(true);
        $mail->Subject = $subject;
        $mail->Body = $htmlBody;
        $mail->AltBody = "Hi {$fullName},\n\n{$intro}\n\nYour code: {$otpCode}\n\nIf you did not request this, you can ignore this email.";

        $mail->send();
        return true;
    } catch (PHPMailerException $e) {
        $GLOBALS['LAST_MAIL_ERROR'] = $mail->ErrorInfo ?: $e->getMessage();
        error_log('sendOtpEmail failed: ' . $GLOBALS['LAST_MAIL_ERROR']);
        return false;
    }
}

/**
 * Delivers one SynapseMail user's message to the recipient's real inbox
 * via SMTP (same mailbox as sendOtpEmail). This is what actually makes
 * "send an email" in the app result in a real email arriving - the row
 * in the `emails` table is the in-app copy, this is the delivery.
 *
 * $ccList / $bccList are arrays of already-validated email addresses
 * (see parseAddressList). $attachments is an array of
 * ['path' => string, 'original_name' => string] pairs - absolute
 * filesystem paths to files already saved on disk (see
 * saveUploadedAttachments), attached to the outgoing message as-is.
 *
 * Returns true if the SMTP server accepted the message for delivery.
 */
function sendMailNotification(
    string $toEmail,
    string $fromName,
    string $fromEmail,
    string $subject,
    string $bodyText,
    array $ccList = [],
    array $bccList = [],
    array $attachments = []
): bool {
    $GLOBALS['LAST_MAIL_ERROR'] = null;
    $safeFromName = htmlspecialchars($fromName, ENT_QUOTES, 'UTF-8');
    $safeSubject = htmlspecialchars($subject, ENT_QUOTES, 'UTF-8');
    $safeBody = nl2br(htmlspecialchars($bodyText, ENT_QUOTES, 'UTF-8'));

    $htmlBody = '<!DOCTYPE html><html><body style="margin:0;padding:0;background-color:#0B0B12;font-family:Arial,Helvetica,sans-serif;">'
        . '<table width="100%" cellpadding="0" cellspacing="0" style="background-color:#0B0B12;padding:32px 0;"><tr><td align="center">'
        . '<table width="480" cellpadding="0" cellspacing="0" style="background-color:#15151f;border-radius:16px;padding:32px;">'
        . '<tr><td align="center" style="padding-bottom:16px;">'
        . '<span style="font-size:18px;font-weight:bold;color:#00E5FF;">Synapse</span>'
        . '<span style="font-size:18px;font-weight:bold;color:#6C5CE7;">Mail</span>'
        . '</td></tr>'
        . '<tr><td style="color:#ffffff;font-size:14px;">'
        . "{$safeFromName} ({$fromEmail}) sent you a message:"
        . '</td></tr>'
        . '<tr><td style="padding-top:16px;">'
        . "<div style=\"color:#ffffff;font-size:16px;font-weight:700;padding-bottom:10px;\">{$safeSubject}</div>"
        . "<div style=\"color:#e5e5ea;font-size:14px;line-height:1.6;\">{$safeBody}</div>"
        . '</td></tr>'
        . '</table></td></tr></table></body></html>';

    $mail = new PHPMailer(true);
    try {
        $mail->isSMTP();
        $mail->Host = SMTP_HOST;
        $mail->SMTPAuth = true;
        $mail->Username = SMTP_USERNAME;
        $mail->Password = SMTP_PASSWORD;
        $mail->Port = SMTP_PORT;
        $mail->SMTPSecure = (SMTP_PORT === 465) ? 'ssl' : 'tls';
        $mail->CharSet = 'UTF-8';

        // Envelope sender must be the real mailbox (Hostinger SMTP requires
        // this), but Reply-To is set to the SynapseMail user's own address
        // so a reply from the recipient's real inbox goes back to them.
        $mail->setFrom(SMTP_USERNAME, "{$fromName} (via SynapseMail)");
        $mail->addAddress($toEmail);
        $mail->addReplyTo($fromEmail, $fromName);

        foreach ($ccList as $cc) {
            $mail->addCC($cc);
        }
        foreach ($bccList as $bcc) {
            $mail->addBCC($bcc);
        }
        foreach ($attachments as $attachment) {
            $mail->addAttachment($attachment['path'], $attachment['original_name']);
        }

        $mail->isHTML(true);
        $mail->Subject = $subject;
        $mail->Body = $htmlBody;
        $mail->AltBody = "{$fromName} ({$fromEmail}) sent you a message:\n\n{$subject}\n\n{$bodyText}";

        $mail->send();
        return true;
    } catch (PHPMailerException $e) {
        $GLOBALS['LAST_MAIL_ERROR'] = $mail->ErrorInfo ?: $e->getMessage();
        error_log('sendMailNotification failed: ' . $GLOBALS['LAST_MAIL_ERROR']);
        return false;
    }
}
