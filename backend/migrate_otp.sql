ALTER TABLE users
    ADD COLUMN email_verified TINYINT(1) NOT NULL DEFAULT 0 AFTER password_hash,
    ADD COLUMN otp_code VARCHAR(6) DEFAULT NULL AFTER email_verified,
    ADD COLUMN otp_expires_at DATETIME DEFAULT NULL AFTER otp_code;
