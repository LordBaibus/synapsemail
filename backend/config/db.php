<?php

define('DB_HOST', 'localhost');
define('DB_NAME', 'u750100575_synapse_email');
define('DB_USER', 'u750100575_synapse');
define('DB_PASS', 'w=7JKHSxe/Z');
define('APP_MAIL_DOMAIN', 'synapsemail.site');
define('SMTP_HOST', 'smtp.hostinger.com');
define('SMTP_PORT', 465);
define('SMTP_USERNAME', 'admin@synapsemail.site');
define('SMTP_PASSWORD', '!Abcd12345678!');
define('SMTP_FROM_NAME', 'SynapseMail');

function getDbConnection(): mysqli {
    $conn = new mysqli(DB_HOST, DB_USER, DB_PASS, DB_NAME);
    if ($conn->connect_error) {
        http_response_code(500);
        echo json_encode(['success' => false, 'message' => 'Database connection failed']);
        exit;
    }
    $conn->set_charset('utf8mb4');
    return $conn;
}
