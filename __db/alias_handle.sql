CREATE TABLE `alias_handle` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `handle` varchar(128) NOT NULL,
  `address` varchar(255) DEFAULT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `pgp_public_key` text DEFAULT NULL,
  `pgp_fingerprint` varchar(64) DEFAULT NULL,
  `pgp_enabled` tinyint(1) NOT NULL DEFAULT 0,
  `pgp_hide_subject` tinyint(1) NOT NULL DEFAULT 0,
  `unsubscribed_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_handle` (`handle`)
) ENGINE=InnoDB AUTO_INCREMENT=26 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;