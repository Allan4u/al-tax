-- SQL untuk membuat tabel yang diperlukan oleh sistem ALTAX

CREATE TABLE IF NOT EXISTS `altax_records` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `identifier` varchar(60) NOT NULL,
  `last_tax_date` timestamp NOT NULL DEFAULT current_timestamp(),
  `next_tax_date` timestamp NOT NULL DEFAULT current_timestamp(),
  `total_tax_paid` int(11) NOT NULL DEFAULT 0,
  `tax_bracket` varchar(50) NOT NULL DEFAULT 'Miskin',
  `tax_rate` float NOT NULL DEFAULT 5.0,
  `overdue_amount` int(11) NOT NULL DEFAULT 0,
  `late_fees` int(11) NOT NULL DEFAULT 0,
  `audit_count` int(11) NOT NULL DEFAULT 0,
  `last_audit_date` timestamp NULL DEFAULT NULL,
  `tax_incentives` longtext DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `altax_payments` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `identifier` varchar(60) NOT NULL,
  `amount` int(11) NOT NULL,
  `tax_type` varchar(50) NOT NULL,
  `payment_date` timestamp NOT NULL DEFAULT current_timestamp(),
  `tax_period_start` timestamp NOT NULL DEFAULT current_timestamp(),
  `tax_period_end` timestamp NOT NULL DEFAULT current_timestamp(),
  `payment_method` varchar(20) NOT NULL DEFAULT 'bank',
  `receipt_id` varchar(50) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `altax_vehicle_tax` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `plate` varchar(12) NOT NULL,
  `owner` varchar(60) NOT NULL,
  `vehicle_model` varchar(60) NOT NULL,
  `purchase_price` int(11) NOT NULL DEFAULT 0,
  `purchase_date` timestamp NOT NULL DEFAULT current_timestamp(),
  `last_tax_date` timestamp NULL DEFAULT NULL,
  `tax_class` varchar(30) NOT NULL DEFAULT 'standard',
  `tax_exemption` tinyint(1) NOT NULL DEFAULT 0,
  `tax_multiplier` float NOT NULL DEFAULT 1.0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `plate` (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `altax_property_tax` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `property_id` varchar(60) NOT NULL,
  `owner` varchar(60) DEFAULT NULL,
  `property_type` varchar(50) NOT NULL DEFAULT 'apartment',
  `property_value` int(11) NOT NULL DEFAULT 0,
  `purchase_date` timestamp NOT NULL DEFAULT current_timestamp(),
  `last_tax_date` timestamp NULL DEFAULT NULL,
  `tax_exemption` tinyint(1) NOT NULL DEFAULT 0,
  `tax_multiplier` float NOT NULL DEFAULT 1.0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `property_id` (`property_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `altax_audit_logs` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `identifier` varchar(60) NOT NULL,
  `audit_date` timestamp NOT NULL DEFAULT current_timestamp(),
  `audit_result` varchar(30) NOT NULL DEFAULT 'pending',
  `tax_owed` int(11) NOT NULL DEFAULT 0,
  `penalties` int(11) NOT NULL DEFAULT 0,
  `audit_officer` varchar(60) DEFAULT NULL,
  `notes` text DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE `owned_vehicles` ADD COLUMN IF NOT EXISTS `purchase_price` int(11) NOT NULL DEFAULT 0;
ALTER TABLE `owned_vehicles` ADD COLUMN IF NOT EXISTS `purchase_date` timestamp NOT NULL DEFAULT current_timestamp();
ALTER TABLE `owned_vehicles` ADD COLUMN IF NOT EXISTS `is_green` tinyint(1) NOT NULL DEFAULT 0;

-- Trigger untuk memperbarui tabel altax_vehicle_tax setiap kali kendaraan baru dibeli
DELIMITER //
CREATE TRIGGER IF NOT EXISTS after_vehicle_insert
AFTER INSERT ON owned_vehicles
FOR EACH ROW
BEGIN
    INSERT INTO altax_vehicle_tax (plate, owner, vehicle_model, purchase_price, purchase_date)
    VALUES (NEW.plate, NEW.owner, NEW.vehicle, NEW.purchase_price, NEW.purchase_date)
    ON DUPLICATE KEY UPDATE
    owner = NEW.owner,
    vehicle_model = NEW.vehicle;
END //
DELIMITER ;