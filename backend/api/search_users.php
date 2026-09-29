<?php
/**
 * Autocomplete endpoint for the compose screen's To/Cc/Bcc fields: given a
 * partial name or email typed so far, returns matching registered users so
 * the app can show them as tappable suggestions (Gmail-style), rather than
 * requiring the sender to type a full address from memory.
 *
 * GET search_users.php?q=<partial text>
 *
 * Matches against both full_name and email (case-insensitive substring
 * match), excludes the requesting user themselves (you don't need to
 * suggest yourself), and only returns verified accounts (an unverified
 * account can't meaningfully receive in-app mail yet). Capped to 8 results
 * - this is a suggestion dropdown, not a full directory browser.
 */
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../config/helpers.php';

sendJsonHeaders();

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    respond(false, 'Method not allowed', [], 405);
}

$conn = getDbConnection();
$user = requireAuth($conn);

$query = trim($_GET['q'] ?? '');

// Require at least 2 characters before hitting the DB - avoids a flood of
// near-useless matches (and load) on every single keystroke starting from
// an empty or one-character field.
if (mb_strlen($query) < 2) {
    respond(true, '', ['users' => []]);
}

$likeTerm = '%' . $conn->real_escape_string($query) . '%';
// real_escape_string above already neutralizes the value for safety, but
// the query still uses a bound parameter (defense in depth / consistency
// with the rest of this codebase's prepared-statement pattern).
$stmt = $conn->prepare(
    'SELECT full_name, email
     FROM users
     WHERE email_verified = 1
       AND email != ?
       AND (full_name LIKE ? OR email LIKE ?)
     ORDER BY full_name ASC
     LIMIT 8'
);
$stmt->bind_param('sss', $user['email'], $likeTerm, $likeTerm);
$stmt->execute();
$result = $stmt->get_result();

$users = [];
while ($row = $result->fetch_assoc()) {
    $users[] = [
        'full_name' => $row['full_name'],
        'email' => $row['email'],
    ];
}

respond(true, '', ['users' => $users]);
