CREATE TABLE IF NOT EXISTS `admin_logs` (
  `id`               INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `action`           VARCHAR(50)  NOT NULL,
  `actor_license`    VARCHAR(60)           DEFAULT NULL,
  `actor_name`       VARCHAR(100) NOT NULL DEFAULT 'console',
  `target_citizenid` VARCHAR(50)           DEFAULT NULL,
  `target_license`   VARCHAR(60)           DEFAULT NULL,
  `target_name`      VARCHAR(100)          DEFAULT NULL,
  `details`          LONGTEXT              DEFAULT NULL,
  `created_at`       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_admin_logs_action`  (`action`),
  KEY `idx_admin_logs_actor`   (`actor_license`),
  KEY `idx_admin_logs_target`  (`target_citizenid`),
  KEY `idx_admin_logs_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
