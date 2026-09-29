-- ============================================================
-- Adds CC/BCC, attachments, and scheduled sending to the emails table.
-- Run this once via Hostinger hPanel > Databases > phpMyAdmin (or the
-- mysql CLI), after the base schema.sql and the earlier migrate_*.sql
-- files have already been applied.
-- ============================================================

-- CC/BCC: stored as comma-separated address lists (simple, matches how
-- this app already keeps recipient_email as a single plain column rather
-- than a normalized table - fine at this scale).
ALTER TABLE emails
    ADD COLUMN cc TEXT DEFAULT NULL AFTER recipient_email,
    ADD COLUMN bcc TEXT DEFAULT NULL AFTER cc;

-- Scheduled sending: a NULL scheduled_at means "send immediately" (the
-- existing behavior). When set, send.php stores the row without actually
-- delivering it yet, and the send_scheduled.php cron script picks it up
-- once scheduled_at has passed.
ALTER TABLE emails
    ADD COLUMN scheduled_at DATETIME DEFAULT NULL AFTER created_at,
    ADD COLUMN status ENUM('sent', 'scheduled', 'failed') NOT NULL DEFAULT 'sent' AFTER scheduled_at,
    ADD INDEX idx_scheduled (status, scheduled_at);

-- Attachments: one row per file, linked to the email it belongs to.
-- Files themselves live on disk under backend/uploads/<email_id>/ - only
-- metadata is stored here.
CREATE TABLE IF NOT EXISTS attachments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    email_id INT NOT NULL,
    original_name VARCHAR(255) NOT NULL,
    stored_name VARCHAR(255) NOT NULL,
    mime_type VARCHAR(127) NOT NULL DEFAULT 'application/octet-stream',
    size_bytes INT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (email_id) REFERENCES emails(id) ON DELETE CASCADE,
    INDEX idx_email (email_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
