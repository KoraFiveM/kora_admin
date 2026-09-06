CREATE TABLE IF NOT EXISTS `admin_reports` (
  `id`                    INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `type`                  VARCHAR(32)   NOT NULL,
  `status`                VARCHAR(16)   NOT NULL DEFAULT 'open',
  `reporter_source`       INT                    DEFAULT NULL,
  `reporter_citizenid`    VARCHAR(50)            DEFAULT NULL,
  `reporter_license`      VARCHAR(60)            DEFAULT NULL,
  `reporter_name`         VARCHAR(100)  NOT NULL,
  `message`               TEXT          NOT NULL,
  `claimed_by_license`    VARCHAR(60)            DEFAULT NULL,
  `claimed_by_name`       VARCHAR(100)           DEFAULT NULL,
  `resolution`            TEXT                   DEFAULT NULL,
  `created_at`            TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`            TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `closed_at`             TIMESTAMP              DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_admin_reports_status` (`status`, `updated_at`),
  KEY `idx_admin_reports_type` (`type`, `updated_at`),
  KEY `idx_admin_reports_reporter` (`reporter_license`, `updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `admin_report_messages` (
  `id`             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `report_id`      INT UNSIGNED NOT NULL,
  `author_license` VARCHAR(60)            DEFAULT NULL,
  `author_name`    VARCHAR(100)  NOT NULL,
  `author_role`    VARCHAR(16)   NOT NULL,
  `message`        TEXT          NOT NULL,
  `created_at`     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_admin_report_messages_report` (`report_id`, `created_at`),
  CONSTRAINT `fk_admin_report_messages_report`
    FOREIGN KEY (`report_id`) REFERENCES `admin_reports` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
