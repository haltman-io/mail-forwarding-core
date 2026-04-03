CREATE TABLE `api_logs` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `api_token_id` bigint(20) unsigned DEFAULT NULL,
  `api_token_owner_email` varchar(254) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `route` varchar(128) NOT NULL,
  `body` longtext DEFAULT NULL,
  `request_ip` varbinary(16) DEFAULT NULL,
  `user_agent` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_api_logs_created_at` (`created_at`),
  KEY `idx_api_logs_token_id` (`api_token_id`),
  KEY `idx_api_logs_owner_email` (`api_token_owner_email`),
  CONSTRAINT `api_logs_ibfk_1` FOREIGN KEY (`api_token_id`) REFERENCES `api_tokens` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=2397 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;