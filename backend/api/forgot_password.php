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

$stmt = $conn->prepare('SELECT id, full_name, email FROM users WHERE email = ? LIMIT 1');
$stmt->bind_param('s', $email);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows === 0) {
    // Do not reveal whether the email exists - respond the same way either
    // way so this endpoint can't be used to enumerate registered accounts.
    respond(true, 'If an account exists for this email, a verification code has been sent.', [
        'email' => $email,
    ]);
}

$user = $result->fetch_assoc();

$otpCode = generateOtpCode();
$otpExpiresAt = date('Y-m-d H:i:s', time() + 600); // 10 minutes

$update = $conn->prepare('UPDATE users SET otp_code = ?, otp_expires_at = ? WHERE id = ?');
$update->bind_param('ssi', $otpCode, $otpExpiresAt, $user['id']);
$update->execute();

$mailSent = sendOtpEmail(
    $user['email'],
    $user['full_name'],
    $otpCode,
    'Your SynapseMail password reset code',
    'Use the verification code below to reset your SynapseMail password. This code expires in 10 minutes. If you did not request a password reset, you can ignore this email.'
);

respond(true, $mailSent
    ? 'If an account exists for this email, a verification code has been sent.'
    : 'Could not send the verification email. Please try again shortly.', [
    'email' => $email,
    'mail_sent' => $mailSent,
    'mail_error' => $mailSent ? null : lastMailError(),
]);
