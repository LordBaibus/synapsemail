ALTER TABLE emails
    ADD COLUMN thread_id INT DEFAULT NULL AFTER deleted_by_recipient,
    ADD COLUMN reply_to_id INT DEFAULT NULL AFTER thread_id,
    ADD INDEX idx_thread (thread_id);
