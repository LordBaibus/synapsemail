<?php
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../config/helpers.php';

sendJsonHeaders();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond(false, 'Method not allowed', [], 405);
}

$body = getJsonBody();
$email = trim(strtolower($body['email'] ?? ''));
$code = trim($body['otp_code'] ?? '');
$newPassword = $body['new_password'] ?? '';

if ($email === '' || $code === '' || $newPassword === '') {
    respond(false, 'email, otp_code and new_password are required', [], 400);
}

if (strlen($newPassword) < 6) {
    respond(false, 'Password must be at least 6 characters', [], 400);
}

$conn = getDbConnection();

$stmt = $conn->prepare('SELECT id, otp_code, otp_expires_at FROM users WHERE email = ? LIMIT 1');
$stmt->bind_param('s', $email);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows === 0) {
    respond(false, 'No account found for this email', [], 404);
}

$user = $result->fetch_assoc();

if ($user['otp_code'] === null || $user['otp_expires_at'] === null) {
    respond(false, 'No reset code is pending. Please request a new one.', [], 400);
}

if (strtotime($user['otp_expires_at']) < time()) {
    respond(false, 'This code has expired. Please request a new one.', [], 400);
}

if (!hash_equals((string) $user['otp_code'], $code)) {
    respond(false, 'Incorrect verification code', [], 401);
}

$passwordHash = password_hash($newPassword, PASSWORD_DEFAULT);

// Reset the password, clear the used code, and invalidate any existing
// session (auth_token) so a stolen token can't survive a password reset.
$update = $conn->prepare(
    'UPDATE users SET password_hash = ?, otp_code = NULL, otp_expires_at = NULL, auth_token = NULL WHERE id = ?'
);
$update->bind_param('si', $passwordHash, $user['id']);
$update->execute();

respond(true, 'Password reset. You can now log in with your new password.');
