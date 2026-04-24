SET SQL_SAFE_UPDATES = 0;

/*
  Script: 02_create_schema_and_seed_mysql.sql
  Goal:
  1) Create database epm_energy
  2) Create tables validation_thresholds, strata, stratum_tariffs,
     meters, readings, and preinvoices
  3) Load seed >= 100 rows (100 meters, 300 readings, and derived preinvoices)

  Compatibility:
  - MySQL 8.0+
  - InnoDB engine
*/

CREATE DATABASE IF NOT EXISTS epm_energy
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE epm_energy;

DROP TABLE IF EXISTS preinvoices;
DROP TABLE IF EXISTS readings;
DROP TABLE IF EXISTS meters;
DROP TABLE IF EXISTS stratum_tariffs;
DROP TABLE IF EXISTS strata;
DROP TABLE IF EXISTS validation_thresholds;

CREATE TABLE validation_thresholds (
    threshold_id BIGINT NOT NULL AUTO_INCREMENT,
    atypical_consumption_pct DECIMAL(6,2) NOT NULL,
    zero_consumption_periods TINYINT NOT NULL,
    negative_reading_min_kwh DECIMAL(18,3) NOT NULL,
    historical_average_months TINYINT NOT NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at_utc TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at_utc TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    PRIMARY KEY (threshold_id),
    CONSTRAINT ck_thresholds_atypical_pct CHECK (atypical_consumption_pct BETWEEN 100.00 AND 10000.00),
    CONSTRAINT ck_thresholds_zero_periods CHECK (zero_consumption_periods BETWEEN 1 AND 12),
    CONSTRAINT ck_thresholds_negative_reading CHECK (negative_reading_min_kwh >= 0),
    CONSTRAINT ck_thresholds_avg_months CHECK (historical_average_months BETWEEN 1 AND 24)
) ENGINE=InnoDB;

CREATE TABLE strata (
    stratum_id TINYINT NOT NULL,
    stratum_name VARCHAR(50) NOT NULL,
    created_at_utc TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (stratum_id),
    UNIQUE KEY uq_strata_name (stratum_name),
    CONSTRAINT ck_strata_id CHECK (stratum_id BETWEEN 1 AND 6)
) ENGINE=InnoDB;

CREATE TABLE stratum_tariffs (
    stratum_tariff_id BIGINT NOT NULL AUTO_INCREMENT,
    stratum_id TINYINT NOT NULL,
    tariff_kwh DECIMAL(12,4) NOT NULL,
    effective_from_date DATE NOT NULL,
    effective_to_date DATE NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at_utc TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (stratum_tariff_id),
    UNIQUE KEY uq_stratum_tariffs_from (stratum_id, effective_from_date),
    KEY ix_stratum_tariffs_active (stratum_id, is_active),
    CONSTRAINT fk_stratum_tariffs_strata FOREIGN KEY (stratum_id) REFERENCES strata(stratum_id),
    CONSTRAINT ck_stratum_tariffs_tariff CHECK (tariff_kwh > 0),
    CONSTRAINT ck_stratum_tariffs_dates CHECK (effective_to_date IS NULL OR effective_to_date > effective_from_date)
) ENGINE=InnoDB;

CREATE TABLE meters (
    meter_id BIGINT NOT NULL AUTO_INCREMENT,
    meter_code VARCHAR(50) NOT NULL,
    customer_id VARCHAR(50) NOT NULL,
    notification_email VARCHAR(320) NOT NULL,
    socioeconomic_stratum TINYINT NOT NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    zero_consumption_periods TINYINT NOT NULL DEFAULT 2,
    increase_threshold_pct DECIMAL(6,2) NOT NULL DEFAULT 300.00,
    average_window_periods TINYINT NOT NULL DEFAULT 6,
    historical_avg_consumption_kwh DECIMAL(18,3) NOT NULL DEFAULT 0,
    tariff_kwh DECIMAL(12,4) NOT NULL,
    created_at_utc TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at_utc TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    PRIMARY KEY (meter_id),
    UNIQUE KEY uq_meters_code (meter_code),
    CONSTRAINT fk_meters_strata FOREIGN KEY (socioeconomic_stratum) REFERENCES strata(stratum_id),
    CONSTRAINT ck_meters_email CHECK (notification_email LIKE '%_@_%._%'),
    CONSTRAINT ck_meters_stratum CHECK (socioeconomic_stratum BETWEEN 1 AND 6),
    CONSTRAINT ck_meters_zero_periods CHECK (zero_consumption_periods BETWEEN 1 AND 12),
    CONSTRAINT ck_meters_threshold CHECK (increase_threshold_pct BETWEEN 100.00 AND 10000.00),
    CONSTRAINT ck_meters_avg_window CHECK (average_window_periods BETWEEN 1 AND 24),
    CONSTRAINT ck_meters_hist_avg CHECK (historical_avg_consumption_kwh >= 0),
    CONSTRAINT ck_meters_tariff CHECK (tariff_kwh > 0)
) ENGINE=InnoDB;

CREATE INDEX ix_meters_customer ON meters(customer_id);

CREATE TABLE readings (
    reading_id BIGINT NOT NULL AUTO_INCREMENT,
    meter_id BIGINT NOT NULL,
    period_date DATE NOT NULL,
    previous_reading DECIMAL(18,3) NOT NULL,
    current_reading DECIMAL(18,3) NOT NULL,
    consumption_kwh DECIMAL(18,3) AS (current_reading - previous_reading) STORED,
    status VARCHAR(10) NOT NULL,
    reason VARCHAR(200) NULL,
    source_file VARCHAR(260) NOT NULL,
    row_hash CHAR(64) NOT NULL,
    created_at_utc TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (reading_id),
    UNIQUE KEY uq_readings_row_hash (row_hash),
    UNIQUE KEY uq_readings_meter_period (meter_id, period_date),
    KEY ix_readings_meter_period (meter_id, period_date DESC),
    KEY ix_readings_status_date (status, created_at_utc DESC),
    CONSTRAINT fk_readings_meters FOREIGN KEY (meter_id) REFERENCES meters(meter_id),
    CONSTRAINT ck_readings_status CHECK (status IN ('ACCEPTED','REJECTED','ANOMALOUS')),
    CONSTRAINT ck_readings_rule1_consistency CHECK (status = 'REJECTED' OR current_reading >= 0),
    CONSTRAINT ck_readings_rule2_consistency CHECK (status = 'REJECTED' OR current_reading >= previous_reading)
) ENGINE=InnoDB;

CREATE TABLE preinvoices (
    preinvoice_id BIGINT NOT NULL AUTO_INCREMENT,
    reading_id BIGINT NOT NULL,
    meter_id BIGINT NOT NULL,
    period_date DATE NOT NULL,
    tariff_kwh DECIMAL(12,4) NOT NULL,
    billable_consumption_kwh DECIMAL(18,3) NOT NULL,
    subtotal DECIMAL(18,2) NOT NULL,
    tax_pct DECIMAL(5,2) NOT NULL DEFAULT 19.00,
    tax_amount DECIMAL(18,2) NOT NULL,
    total_amount DECIMAL(18,2) NOT NULL,
    notification_status VARCHAR(15) NOT NULL DEFAULT 'PENDING',
    created_at_utc TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (preinvoice_id),
    UNIQUE KEY uq_preinvoices_reading (reading_id),
    KEY ix_preinvoices_meter_period (meter_id, period_date DESC),
    CONSTRAINT fk_preinvoices_readings FOREIGN KEY (reading_id) REFERENCES readings(reading_id),
    CONSTRAINT fk_preinvoices_meters FOREIGN KEY (meter_id) REFERENCES meters(meter_id),
    CONSTRAINT ck_preinvoices_amounts CHECK (
        tariff_kwh > 0 AND
        billable_consumption_kwh >= 0 AND
        subtotal >= 0 AND
        tax_pct BETWEEN 0 AND 100 AND
        tax_amount >= 0 AND
        total_amount >= 0
    ),
    CONSTRAINT ck_preinvoices_notif_status CHECK (notification_status IN ('PENDING','SENT','ERROR'))
) ENGINE=InnoDB;

/* Seed: validation thresholds */
INSERT INTO validation_thresholds (
    atypical_consumption_pct,
    zero_consumption_periods,
    negative_reading_min_kwh,
    historical_average_months,
    is_active
)
VALUES
    (300.00, 3, 0.000, 6, 1);

/* Seed: strata */
INSERT INTO strata (stratum_id, stratum_name)
VALUES
    (1, 'ESTRATO_1'),
    (2, 'ESTRATO_2'),
    (3, 'ESTRATO_3'),
    (4, 'ESTRATO_4'),
    (5, 'ESTRATO_5'),
    (6, 'ESTRATO_6');

/* Seed: active tariff per stratum */
INSERT INTO stratum_tariffs (
    stratum_id,
    tariff_kwh,
    effective_from_date,
    effective_to_date,
    is_active
)
VALUES
    (1, 620.0000, '2026-01-01', NULL, 1),
    (2, 650.0000, '2026-01-01', NULL, 1),
    (3, 690.0000, '2026-01-01', NULL, 1),
    (4, 740.0000, '2026-01-01', NULL, 1),
    (5, 790.0000, '2026-01-01', NULL, 1),
    (6, 840.0000, '2026-01-01', NULL, 1);

/* Seed: 100 meters
    Seed requirements covered:
    - At least 50 test meters (we load 100)
    - Strata variety (1..6)
    - Historical averages include low values to allow Rule 4 trigger on uploaded CSV
*/
WITH RECURSIVE seq AS (
    SELECT 1 AS num
    UNION ALL
    SELECT num + 1 FROM seq WHERE num < 100
)
INSERT INTO meters (
    meter_code,
    customer_id,
    notification_email,
    socioeconomic_stratum,
    is_active,
    zero_consumption_periods,
    increase_threshold_pct,
    average_window_periods,
    historical_avg_consumption_kwh,
    tariff_kwh
)
SELECT
    CONCAT('MTR-', LPAD(num, 6, '0')) AS meter_code,
    CONCAT('CUS-', LPAD(num, 6, '0')) AS customer_id,
    CONCAT('customer', num, '@epm.local') AS notification_email,
    CAST(((num - 1) % 6) + 1 AS UNSIGNED) AS socioeconomic_stratum,
    1 AS is_active,
    CASE WHEN num % 10 = 0 THEN 3 ELSE 2 END AS zero_consumption_periods,
    CASE
        WHEN num % 7 = 0 THEN 250.00
        WHEN num % 5 = 0 THEN 350.00
        ELSE 300.00
    END AS increase_threshold_pct,
    CASE
        WHEN num % 8 = 0 THEN 12
        WHEN num % 3 = 0 THEN 9
        ELSE 6
    END AS average_window_periods,
    CAST(
        CASE
            WHEN num % 15 = 0 THEN 10
            WHEN num % 9 = 0 THEN 15
            ELSE 80 + (num % 40)
        END AS DECIMAL(18,3)
    ) AS historical_avg_consumption_kwh,
    CAST(0 AS DECIMAL(12,4)) AS tariff_kwh
FROM seq;

/* Seed requirement check: should return status = OK */
SELECT
    COUNT(*) AS meters_seeded,
    CASE WHEN COUNT(*) >= 50 THEN 'OK' ELSE 'FAIL_MIN_50' END AS status
FROM meters;

/* Keep tariff_kwh aligned to active tariff by stratum for backward compatibility */
UPDATE meters m
INNER JOIN stratum_tariffs st
    ON st.stratum_id = m.socioeconomic_stratum
   AND st.is_active = 1
SET m.tariff_kwh = st.tariff_kwh;

/* Seed: 300 readings (3 periods per meter)
    - January: ACCEPTED (for selected meters, consumption = 0)
    - February: ACCEPTED or ANOMALOUS (0 consumption for selected meters)
    - March: ACCEPTED, ANOMALOUS (3rd zero), or REJECTED (current lower than previous)
    This guarantees prior readings to validate:
    - Rule 2 (current reading lower than previous)
    - Rule 3 (three periods in zero for selected meters)
*/
INSERT INTO readings (
    meter_id,
    period_date,
    previous_reading,
    current_reading,
    status,
    reason,
    source_file,
    row_hash
)
SELECT
    base_rows.meter_id,
    base_rows.period_date,
    base_rows.previous_reading,
    base_rows.current_reading,
    base_rows.status,
    base_rows.reason,
    base_rows.source_file,
    LOWER(SHA2(CONCAT(base_rows.meter_code, '|', DATE_FORMAT(base_rows.period_date, '%Y-%m-%d'), '|', base_rows.current_reading, '|', base_rows.source_file), 256)) AS row_hash
FROM (
    SELECT
        m.meter_id,
        m.meter_code,
        DATE('2026-01-01') AS period_date,
        CAST(1000 + m.meter_id * 10 AS DECIMAL(18,3)) AS previous_reading,
        CAST(
            CASE
                WHEN m.meter_id % 20 = 0 THEN 1000 + m.meter_id * 10
                ELSE 1000 + m.meter_id * 10 + (50 + (m.meter_id % 30))
            END AS DECIMAL(18,3)
        ) AS current_reading,
        'ACCEPTED' AS status,
        NULL AS reason,
        'readings-2026-01.csv' AS source_file
    FROM meters m

    UNION ALL

    SELECT
        m.meter_id,
        m.meter_code,
        DATE('2026-02-01') AS period_date,
        CAST(1000 + m.meter_id * 10 + (50 + (m.meter_id % 30)) AS DECIMAL(18,3)) AS previous_reading,
        CAST(
            CASE
                WHEN m.meter_id % 20 = 0 THEN 1000 + m.meter_id * 10 + (50 + (m.meter_id % 30))
                ELSE 1000 + m.meter_id * 10 + (50 + (m.meter_id % 30)) + (40 + (m.meter_id % 25))
            END AS DECIMAL(18,3)
        ) AS current_reading,
        CASE WHEN m.meter_id % 20 = 0 THEN 'ANOMALOUS' ELSE 'ACCEPTED' END AS status,
        CASE WHEN m.meter_id % 20 = 0 THEN 'R3_ZERO_CONSUMPTION_STREAK' ELSE NULL END AS reason,
        'readings-2026-02.csv' AS source_file
    FROM meters m

    UNION ALL

    SELECT
        m.meter_id,
        m.meter_code,
        DATE('2026-03-01') AS period_date,
        CAST(
            CASE
                WHEN m.meter_id % 20 = 0 THEN 1000 + m.meter_id * 10 + (50 + (m.meter_id % 30))
                ELSE 1000 + m.meter_id * 10 + (50 + (m.meter_id % 30)) + (40 + (m.meter_id % 25))
            END AS DECIMAL(18,3)
        ) AS previous_reading,
        CAST(
            CASE
                WHEN m.meter_id % 25 = 0 THEN
                    (CASE WHEN m.meter_id % 20 = 0 THEN 1000 + m.meter_id * 10 + (50 + (m.meter_id % 30)) ELSE 1000 + m.meter_id * 10 + (50 + (m.meter_id % 30)) + (40 + (m.meter_id % 25)) END) - 5
                WHEN m.meter_id % 20 = 0 THEN
                    (CASE WHEN m.meter_id % 20 = 0 THEN 1000 + m.meter_id * 10 + (50 + (m.meter_id % 30)) ELSE 1000 + m.meter_id * 10 + (50 + (m.meter_id % 30)) + (40 + (m.meter_id % 25)) END)
                ELSE
                    (CASE WHEN m.meter_id % 20 = 0 THEN 1000 + m.meter_id * 10 + (50 + (m.meter_id % 30)) ELSE 1000 + m.meter_id * 10 + (50 + (m.meter_id % 30)) + (40 + (m.meter_id % 25)) END) + (45 + (m.meter_id % 20))
            END AS DECIMAL(18,3)
        ) AS current_reading,
        CASE
            WHEN m.meter_id % 25 = 0 THEN 'REJECTED'
            WHEN m.meter_id % 20 = 0 THEN 'ANOMALOUS'
            ELSE 'ACCEPTED'
        END AS status,
        CASE
            WHEN m.meter_id % 25 = 0 THEN 'R2_CURRENT_LOWER_THAN_PREVIOUS'
            WHEN m.meter_id % 20 = 0 THEN 'R3_ZERO_CONSUMPTION_STREAK'
            ELSE NULL
        END AS reason,
        'readings-2026-03.csv' AS source_file
    FROM meters m
) AS base_rows;

/* Seed: preinvoices for ACCEPTED readings */
INSERT INTO preinvoices (
    reading_id,
    meter_id,
    period_date,
    tariff_kwh,
    billable_consumption_kwh,
    subtotal,
    tax_pct,
    tax_amount,
    total_amount,
    notification_status
)
SELECT
    r.reading_id,
    r.meter_id,
    r.period_date,
    st.tariff_kwh,
    r.consumption_kwh,
    CAST(r.consumption_kwh * st.tariff_kwh AS DECIMAL(18,2)) AS subtotal,
    19.00 AS tax_pct,
    CAST((r.consumption_kwh * st.tariff_kwh) * 0.19 AS DECIMAL(18,2)) AS tax_amount,
    CAST((r.consumption_kwh * st.tariff_kwh) * 1.19 AS DECIMAL(18,2)) AS total_amount,
    CASE WHEN r.meter_id % 11 = 0 THEN 'SENT' ELSE 'PENDING' END AS notification_status
FROM readings r
INNER JOIN meters m ON m.meter_id = r.meter_id
INNER JOIN stratum_tariffs st
    ON st.stratum_id = m.socioeconomic_stratum
   AND st.is_active = 1
WHERE r.status = 'ACCEPTED';

/* Quick seed volume check */
SELECT 'meters' AS table_name, COUNT(*) AS total FROM meters
UNION ALL
SELECT 'readings' AS table_name, COUNT(*) AS total FROM readings
UNION ALL
SELECT 'preinvoices' AS table_name, COUNT(*) AS total FROM preinvoices
UNION ALL
SELECT 'validation_thresholds' AS table_name, COUNT(*) AS total FROM validation_thresholds
UNION ALL
SELECT 'strata' AS table_name, COUNT(*) AS total FROM strata
UNION ALL
SELECT 'stratum_tariffs' AS table_name, COUNT(*) AS total FROM stratum_tariffs;
