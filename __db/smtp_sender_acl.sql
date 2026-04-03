CREATE TABLE `smtp_sender_acl` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `login` varchar(320) NOT NULL,
  `sender` varchar(320) NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_login_sender` (`login`,`sender`)
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;