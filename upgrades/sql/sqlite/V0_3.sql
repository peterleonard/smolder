ALTER TABLE preference ADD COLUMN email_limit INTEGER DEFAULT 0;
ALTER TABLE preference ADD COLUMN email_sent INTEGER DEFAULT 0;
ALTER TABLE preference ADD COLUMN email_sent_timestamp INTEGER;