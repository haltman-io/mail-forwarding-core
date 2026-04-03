CREATE TABLE `alias` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `address` varchar(320) NOT NULL,
  `goto` text NOT NULL,
  `active` tinyint(1) DEFAULT 1,
  `created` timestamp NULL DEFAULT current_timestamp(),
  `modified` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_alias_address` (`address`),
  KEY `idx_alias_goto_id` (`goto`(191),`id`),
  KEY `idx_alias_goto_created` (`goto`(191),`created`),
  KEY `idx_alias_goto_modified` (`goto`(191),`modified`)
) ENGINE=InnoDB AUTO_INCREMENT=1299 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;