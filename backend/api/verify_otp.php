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

if ($email === '' || $code === '') {
    respond(false, 'email and otp_code are required', [], 400);
}

$conn = getDbConnection();

$stmt = $conn->prepare('SELECT id, full_name, email, email_verified, otp_code, otp_expires_at FROM users WHERE email = ? LIMIT 1');
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

if ($user['otp_code'] === null || $user['otp_expires_at'] === null) {
    respond(false, 'No verification code is pending. Please request a new one.', [], 400);
}

if (strtotime($user['otp_expires_at']) < time()) {
    respond(false, 'This code has expired. Please request a new one.', [], 400);
}

if (!hash_equals((string) $user['otp_code'], $code)) {
    respond(false, 'Incorrect verification code', [], 401);
}

$token = generateToken();
$update = $conn->prepare(
    'UPDATE users SET email_verified = 1, otp_code = NULL, otp_expires_at = NULL, auth_token = ? WHERE id = ?'
);
$update->bind_param('si', $token, $user['id']);
$update->execute();

respond(true, 'Email verified', [
    'token' => $token,
    'user' => [
        'id' => $user['id'],
        'full_name' => $user['full_name'],
        'email' => $user['email'],
    ],
]);
