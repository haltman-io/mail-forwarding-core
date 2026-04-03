CREATE TABLE `api_tokens` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `owner_email` varchar(254) NOT NULL,
  `token_hash` binary(32) NOT NULL,
  `status` enum('active','revoked','expired') NOT NULL DEFAULT 'active',
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `expires_at` datetime(6) NOT NULL,
  `revoked_at` datetime(6) DEFAULT NULL,
  `revoked_reason` varchar(500) DEFAULT NULL,
  `created_ip` varbinary(16) DEFAULT NULL,
  `user_agent` varchar(255) DEFAULT NULL,
  `last_used_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_api_tokens_token_hash` (`token_hash`),
  KEY `idx_api_tokens_owner_email` (`owner_email`),
  KEY `idx_api_tokens_expires_at` (`expires_at`),
  KEY `idx_api_tokens_status` (`status`)
) ENGINE=InnoDB AUTO_INCREMENT=48 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;