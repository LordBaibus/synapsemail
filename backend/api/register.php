<?php
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../config/helpers.php';

sendJsonHeaders();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond(false, 'Method not allowed', [], 405);
}

$body = getJsonBody();
$fullName = trim($body['full_name'] ?? '');
$email = trim(strtolower($body['email'] ?? ''));
$password = $body['password'] ?? '';

if ($fullName === '' || $email === '' || $password === '') {
    respond(false, 'full_name, email and password are required', [], 400);
}

if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    respond(false, 'Invalid email address', [], 400);
}

if (strlen($password) < 6) {
    respond(false, 'Password must be at least 6 characters', [], 400);
}

$conn = getDbConnection();

$stmt = $conn->prepare('SELECT id FROM users WHERE email = ? LIMIT 1');
$stmt->bind_param('s', $email);
$stmt->execute();
if ($stmt->get_result()->num_rows > 0) {
    respond(false, 'An account with this email already exists', [], 409);
}

$passwordHash = password_hash($password, PASSWORD_DEFAULT);
$otpCode = generateOtpCode();
$otpExpiresAt = date('Y-m-d H:i:s', time() + 600); // 10 minutes

// No auth_token is issued here - the account stays unverified
// (email_verified = 0) until the code is confirmed via verify_otp.php.
$stmt = $conn->prepare(
    'INSERT INTO users (full_name, email, password_hash, email_verified, otp_code, otp_expires_at) VALUES (?, ?, ?, 0, ?, ?)'
);
$stmt->bind_param('sssss', $fullName, $email, $passwordHash, $otpCode, $otpExpiresAt);

if (!$stmt->execute()) {
    respond(false, 'Failed to create account', [], 500);
}

$mailSent = sendOtpEmail($email, $fullName, $otpCode);

respond(true, $mailSent
    ? 'Account created. Check your email for a 6-digit verification code.'
    : 'Account created, but the verification email could not be sent. Try resending the code.', [
    'email' => $email,
    'mail_sent' => $mailSent,
    'mail_error' => $mailSent ? null : lastMailError(),
]);
