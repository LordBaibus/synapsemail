<?php
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../config/helpers.php';

sendJsonHeaders();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond(false, 'Method not allowed', [], 405);
}

$body = getJsonBody();
$email = trim(strtolower($body['email'] ?? ''));
$password = $body['password'] ?? '';

if ($email === '' || $password === '') {
    respond(false, 'email and password are required', [], 400);
}

$conn = getDbConnection();

$stmt = $conn->prepare('SELECT id, full_name, email, password_hash, email_verified FROM users WHERE email = ? LIMIT 1');
$stmt->bind_param('s', $email);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows === 0) {
    respond(false, 'Invalid email or password', [], 401);
}

$user = $result->fetch_assoc();

if (!password_verify($password, $user['password_hash'])) {
    respond(false, 'Invalid email or password', [], 401);
}

if ((int) $user['email_verified'] !== 1) {
    respond(false, 'Please verify your email before logging in. We can resend your code.', [
        'needs_verification' => true,
        'email' => $user['email'],
    ], 403);
}

$token = generateToken();
$update = $conn->prepare('UPDATE users SET auth_token = ? WHERE id = ?');
$update->bind_param('si', $token, $user['id']);
$update->execute();

respond(true, 'Logged in', [
    'token' => $token,
    'user' => [
        'id' => $user['id'],
        'full_name' => $user['full_name'],
        'email' => $user['email'],
    ],
]);
