<?php
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../config/helpers.php';

sendJsonHeaders();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond(false, 'Method not allowed', [], 405);
}

$body = getJsonBody();
$email = trim(strtolower($body['email'] ?? ''));

if ($email === '') {
    respond(false, 'email is required', [], 400);
}

$conn = getDbConnection();

$stmt = $conn->prepare('SELECT id, full_name, email, email_verified FROM users WHERE email = ? LIMIT 1');
$stmt->bind_param('s', $email);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows === 0) {
    respond(false, 'No account found for this email', [], 404);
}

$user = $result->fetch_assoc();

if ((int) $user['email_verified'] === 1) {
    respond(false, 'This account is already verified. Please log in.', [], 409);
}

$otpCode = generateOtpCode();
$otpExpiresAt = date('Y-m-d H:i:s', time() + 600); // 10 minutes

$update = $conn->prepare('UPDATE users SET otp_code = ?, otp_expires_at = ? WHERE id = ?');
$update->bind_param('ssi', $otpCode, $otpExpiresAt, $user['id']);
$update->execute();

$mailSent = sendOtpEmail($user['email'], $user['full_name'], $otpCode);

respond(true, $mailSent
    ? 'A new verification code has been sent to your email.'
    : 'Could not send the verification email. Please try again shortly.', [
    'mail_sent' => $mailSent,
    'mail_error' => $mailSent ? null : lastMailError(),
]);
