CREATE TABLE `api_bans` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `ban_type` enum('email','domain','ip','name') NOT NULL,
  `ban_value` varchar(254) NOT NULL,
  `reason` varchar(500) NOT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `expires_at` datetime(6) DEFAULT NULL,
  `revoked_at` datetime(6) DEFAULT NULL,
  `revoked_reason` varchar(500) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_active_target` (`ban_type`,`ban_value`,`revoked_at`),
  KEY `idx_lookup` (`ban_type`,`ban_value`),
  KEY `idx_expires_at` (`expires_at`),
  KEY `idx_revoked_at` (`revoked_at`),
  KEY `idx_api_bans_type_value_active` (`ban_type`,`ban_value`,`revoked_at`,`expires_at`)
) ENGINE=InnoDB AUTO_INCREMENT=57 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;