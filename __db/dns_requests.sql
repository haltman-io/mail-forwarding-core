CREATE TABLE `dns_requests` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `target` varchar(253) NOT NULL,
  `type` enum('UI','EMAIL') NOT NULL,
  `status` varchar(16) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `activated_at` datetime DEFAULT NULL,
  `last_checked_at` datetime DEFAULT NULL,
  `next_check_at` datetime DEFAULT NULL,
  `last_check_result_json` text DEFAULT NULL,
  `fail_reason` text DEFAULT NULL,
  `expires_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_target_type` (`target`,`type`),
  KEY `idx_status` (`status`),
  KEY `idx_expires_at` (`expires_at`)
) ENGINE=InnoDB AUTO_INCREMENT=184 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;