<?php
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../config/helpers.php';

sendJsonHeaders();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond(false, 'Method not allowed', [], 405);
}

$conn = getDbConnection();
$user = requireAuth($conn);

$stmt = $conn->prepare('UPDATE users SET auth_token = NULL WHERE id = ?');
$stmt->bind_param('i', $user['id']);
$stmt->execute();

respond(true, 'Logged out');
