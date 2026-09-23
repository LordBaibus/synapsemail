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
 * Returns true if the SMTP server accepted the message for delivery.
 */
function sendMailNotification(string $toEmail, string $fromName, string $fromEmail, string $subject, string $bodyText): bool {
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
