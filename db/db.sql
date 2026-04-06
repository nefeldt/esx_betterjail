ALTER TABLE users ADD COLUMN jail_time INT DEFAULT 0;

CREATE TABLE IF NOT EXISTS `jail_logs` (
    `id`                   INT AUTO_INCREMENT PRIMARY KEY,
    `action`               VARCHAR(20)  NOT NULL,
    `officer_name`         VARCHAR(255) DEFAULT NULL,
    `officer_identifier`   VARCHAR(255) DEFAULT NULL,
    `prisoner_name`        VARCHAR(255) NOT NULL,
    `prisoner_identifier`  VARCHAR(255) NOT NULL,
    `duration`             INT          DEFAULT 0,
    `reason`               VARCHAR(500) DEFAULT NULL,
    `created_at`           TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_prisoner  (`prisoner_identifier`),
    INDEX idx_created   (`created_at`)
);
