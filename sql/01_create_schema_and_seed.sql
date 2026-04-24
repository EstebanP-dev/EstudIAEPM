SET NOCOUNT ON;

/*
  Script: 01_create_schema_and_seed.sql
  Goal:
  1) Create dbo.validation_thresholds, dbo.strata, dbo.stratum_tariffs,
      dbo.meters, dbo.readings, and dbo.preinvoices tables
  2) Load seed >= 100 rows (100 meters, 300 readings, and derived preinvoices)
    3) Add relational and validation constraints after the seed so they validate the loaded data

  Azure SQL note:
  - If you are already connected to the target database, do not use CREATE DATABASE/USE.
*/

BEGIN TRY
    BEGIN TRANSACTION;

    /* Controlled cleanup to support re-runs */
    IF OBJECT_ID('dbo.preinvoices', 'U') IS NOT NULL
        DROP TABLE dbo.preinvoices;

    IF OBJECT_ID('dbo.readings', 'U') IS NOT NULL
        DROP TABLE dbo.readings;

    IF OBJECT_ID('dbo.meters', 'U') IS NOT NULL
        DROP TABLE dbo.meters;

    IF OBJECT_ID('dbo.stratum_tariffs', 'U') IS NOT NULL
        DROP TABLE dbo.stratum_tariffs;

    IF OBJECT_ID('dbo.strata', 'U') IS NOT NULL
        DROP TABLE dbo.strata;

    IF OBJECT_ID('dbo.validation_thresholds', 'U') IS NOT NULL
        DROP TABLE dbo.validation_thresholds;

    /* 1) Validation thresholds table (global configurable limits) */
    CREATE TABLE dbo.validation_thresholds (
        threshold_id                      BIGINT IDENTITY(1,1) NOT NULL,
        atypical_consumption_pct          DECIMAL(6,2) NOT NULL,
        zero_consumption_periods          TINYINT NOT NULL,
        negative_reading_min_kwh          DECIMAL(18,3) NOT NULL,
        historical_average_months         TINYINT NOT NULL,
        is_active                         BIT NOT NULL CONSTRAINT DF_thresholds_active DEFAULT (1),
        created_at_utc                    DATETIME2(3) NOT NULL CONSTRAINT DF_thresholds_created DEFAULT (SYSUTCDATETIME()),
        updated_at_utc                    DATETIME2(3) NOT NULL CONSTRAINT DF_thresholds_updated DEFAULT (SYSUTCDATETIME())
    );

    CREATE UNIQUE INDEX UX_thresholds_single_active
        ON dbo.validation_thresholds (is_active)
        WHERE is_active = 1;

    /* 2) Socioeconomic strata and tariffs */
    CREATE TABLE dbo.strata (
        stratum_id                        TINYINT NOT NULL,
        stratum_name                      NVARCHAR(50) NOT NULL,
        created_at_utc                    DATETIME2(3) NOT NULL CONSTRAINT DF_strata_created DEFAULT (SYSUTCDATETIME())
    );

    CREATE TABLE dbo.stratum_tariffs (
        stratum_tariff_id                 BIGINT IDENTITY(1,1) NOT NULL,
        stratum_id                        TINYINT NOT NULL,
        tariff_kwh                        DECIMAL(12,4) NOT NULL,
        effective_from_date               DATE NOT NULL,
        effective_to_date                 DATE NULL,
        is_active                         BIT NOT NULL CONSTRAINT DF_stratum_tariffs_active DEFAULT (1),
        created_at_utc                    DATETIME2(3) NOT NULL CONSTRAINT DF_stratum_tariffs_created DEFAULT (SYSUTCDATETIME())
    );

    CREATE UNIQUE INDEX UX_stratum_tariffs_active
        ON dbo.stratum_tariffs (stratum_id)
        WHERE is_active = 1;

    /* 3) Meters table */
    CREATE TABLE dbo.meters (
        meter_id                         BIGINT IDENTITY(1,1) NOT NULL,
        meter_code                       NVARCHAR(50) NOT NULL,
        customer_id                      NVARCHAR(50) NOT NULL,
        address                          NVARCHAR(200) NOT NULL,
        notification_email               NVARCHAR(320) NOT NULL,
        socioeconomic_stratum            TINYINT NOT NULL,
        is_active                        BIT NOT NULL CONSTRAINT DF_meters_is_active DEFAULT (1),
        zero_consumption_periods         TINYINT NOT NULL CONSTRAINT DF_meters_zero_periods DEFAULT (2),
        increase_threshold_pct           DECIMAL(6,2) NOT NULL CONSTRAINT DF_meters_threshold DEFAULT (300.00),
        average_window_periods           TINYINT NOT NULL CONSTRAINT DF_meters_avg_window DEFAULT (6),
        historical_avg_consumption_kwh   DECIMAL(18,3) NOT NULL CONSTRAINT DF_meters_hist_avg DEFAULT (0),
        tariff_kwh                       DECIMAL(12,4) NOT NULL,
        created_at_utc                   DATETIME2(3) NOT NULL CONSTRAINT DF_meters_created DEFAULT (SYSUTCDATETIME()),
        updated_at_utc                   DATETIME2(3) NOT NULL CONSTRAINT DF_meters_updated DEFAULT (SYSUTCDATETIME())
    );

    CREATE INDEX IX_meters_customer ON dbo.meters(customer_id);

    /* 4) Readings table */
    CREATE TABLE dbo.readings (
        reading_id                        BIGINT IDENTITY(1,1) NOT NULL,
        meter_id                          BIGINT NOT NULL,
        period_date                       DATE NOT NULL,
        previous_reading                  DECIMAL(18,3) NOT NULL,
        current_reading                   DECIMAL(18,3) NOT NULL,
        consumption_kwh                   AS (current_reading - previous_reading) PERSISTED,
        status                            VARCHAR(10) NOT NULL, -- ACCEPTED | REJECTED | ANOMALOUS
        reason                            NVARCHAR(200) NULL,
        source_file                       NVARCHAR(260) NOT NULL,
        row_hash                          CHAR(64) NOT NULL,
        created_at_utc                    DATETIME2(3) NOT NULL CONSTRAINT DF_readings_created DEFAULT (SYSUTCDATETIME())
    );

    CREATE INDEX IX_readings_meter_period ON dbo.readings(meter_id, period_date DESC);
    CREATE INDEX IX_readings_status_date ON dbo.readings(status, created_at_utc DESC);

    /* 5) Preinvoices table */
    CREATE TABLE dbo.preinvoices (
        preinvoice_id                    BIGINT IDENTITY(1,1) NOT NULL,
        reading_id                       BIGINT NOT NULL,
        meter_id                         BIGINT NOT NULL,
        period_date                      DATE NOT NULL,
        tariff_kwh                       DECIMAL(12,4) NOT NULL,
        billable_consumption_kwh         DECIMAL(18,3) NOT NULL,
        subtotal                         DECIMAL(18,2) NOT NULL,
        tax_pct                          DECIMAL(5,2) NOT NULL CONSTRAINT DF_preinvoices_tax DEFAULT (19.00),
        tax_amount                       DECIMAL(18,2) NOT NULL,
        total_amount                     DECIMAL(18,2) NOT NULL,
        notification_status              VARCHAR(15) NOT NULL CONSTRAINT DF_preinvoices_notif DEFAULT ('PENDING'),
        manual_review_pending            BIT NOT NULL CONSTRAINT DF_preinvoices_manual_review DEFAULT (0),
        notification_date_utc            DATETIME2(3) NULL,
        created_at_utc                   DATETIME2(3) NOT NULL CONSTRAINT DF_preinvoices_created DEFAULT (SYSUTCDATETIME())
    );

    CREATE INDEX IX_preinvoices_meter_period ON dbo.preinvoices(meter_id, period_date DESC);

    /* Seed: validation thresholds */
    INSERT INTO dbo.validation_thresholds (
        atypical_consumption_pct,
        zero_consumption_periods,
        negative_reading_min_kwh,
        historical_average_months,
        is_active
    )
    VALUES
        (300.00, 3, 0.000, 6, 1);

    /* Seed: strata */
    INSERT INTO dbo.strata (stratum_id, stratum_name)
    VALUES
        (1, N'ESTRATO_1'),
        (2, N'ESTRATO_2'),
        (3, N'ESTRATO_3'),
        (4, N'ESTRATO_4'),
        (5, N'ESTRATO_5'),
        (6, N'ESTRATO_6');

    /* Seed: active tariff per stratum */
    INSERT INTO dbo.stratum_tariffs (
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
    ;WITH n AS (
        SELECT TOP (100)
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS num
        FROM sys.all_objects
    )
    INSERT INTO dbo.meters (
        meter_code,
        customer_id,
        address,
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
        CONCAT('MTR-', RIGHT(CONCAT('000000', num), 6)) AS meter_code,
        CONCAT('CUS-', RIGHT(CONCAT('000000', num), 6)) AS customer_id,
        CONCAT('Calle ', num, ' #', RIGHT(CONCAT('00', num % 100), 2), '-01') AS address,
        CONCAT('customer', num, '@epm.local') AS notification_email,
        CAST(((num - 1) % 6) + 1 AS TINYINT) AS socioeconomic_stratum,
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
    FROM n;

    IF (SELECT COUNT(1) FROM dbo.meters) < 50
        THROW 50001, 'Seed requirement not met: at least 50 meters are required.', 1;

    /* Keep tariff_kwh aligned to active tariff by stratum for backward compatibility */
    UPDATE m
    SET m.tariff_kwh = st.tariff_kwh
    FROM dbo.meters m
    INNER JOIN dbo.stratum_tariffs st
        ON st.stratum_id = m.socioeconomic_stratum
       AND st.is_active = 1;

        /* Seed: 300 readings (3 periods per meter)
            - January: ACCEPTED (for selected meters, consumption = 0)
            - February: ACCEPTED (keeps the zero streak alive for the selected meters)
            - March: ACCEPTED, ANOMALOUS (3rd zero or atypical consumption), or REJECTED (current lower than previous)
         This guarantees prior readings to validate:
         - Rule 2 (current reading lower than previous)
         - Rule 3 (three periods in zero for selected meters)
    */
    ;WITH base AS (
        SELECT
            m.meter_id,
            m.meter_code,
            CAST(1000 + m.meter_id * 10 AS DECIMAL(18,3)) AS jan_prev,
            CAST(
                CASE
                    WHEN m.meter_id % 20 = 0 THEN 1000 + m.meter_id * 10
                    ELSE 1000 + m.meter_id * 10 + (50 + (m.meter_id % 30))
                END AS DECIMAL(18,3)
            ) AS jan_curr
        FROM dbo.meters m
    ),
    periods AS (
        SELECT
            b.meter_id,
            b.meter_code,
            CAST('2026-01-01' AS DATE) AS period_date,
            b.jan_prev AS previous_reading,
            b.jan_curr AS current_reading,
            CAST('ACCEPTED' AS VARCHAR(10)) AS status,
            CAST(NULL AS NVARCHAR(200)) AS reason,
            CAST('readings-2026-01.csv' AS NVARCHAR(260)) AS source_file
        FROM base b

        UNION ALL

        SELECT
            b.meter_id,
            b.meter_code,
            CAST('2026-02-01' AS DATE) AS period_date,
            b.jan_curr AS previous_reading,
            CAST(
                CASE
                    WHEN b.meter_id % 20 = 0 THEN b.jan_curr
                    ELSE b.jan_curr + (40 + (b.meter_id % 25))
                END AS DECIMAL(18,3)
            ) AS current_reading,
            CAST('ACCEPTED' AS VARCHAR(10)) AS status,
            CAST(NULL AS NVARCHAR(200)) AS reason,
            CAST('readings-2026-02.csv' AS NVARCHAR(260)) AS source_file
        FROM base b

        UNION ALL

        SELECT
            b.meter_id,
            b.meter_code,
            CAST('2026-03-01' AS DATE) AS period_date,
            CAST(
                CASE
                    WHEN b.meter_id % 20 = 0 THEN b.jan_curr
                    ELSE b.jan_curr + (40 + (b.meter_id % 25))
                END AS DECIMAL(18,3)
            ) AS previous_reading,
            CAST(
                CASE
                    WHEN b.meter_id % 25 = 0 THEN
                        (CASE WHEN b.meter_id % 20 = 0 THEN b.jan_curr ELSE b.jan_curr + (40 + (b.meter_id % 25)) END) - 5
                    WHEN b.meter_id % 20 = 0 THEN
                        (CASE WHEN b.meter_id % 20 = 0 THEN b.jan_curr ELSE b.jan_curr + (40 + (b.meter_id % 25)) END)
                    WHEN b.meter_id % 15 = 0 THEN
                        (CASE WHEN b.meter_id % 20 = 0 THEN b.jan_curr ELSE b.jan_curr + (40 + (b.meter_id % 25)) END) * 6
                    ELSE
                        (CASE WHEN b.meter_id % 20 = 0 THEN b.jan_curr ELSE b.jan_curr + (40 + (b.meter_id % 25)) END) + (45 + (b.meter_id % 20))
                END AS DECIMAL(18,3)
            ) AS current_reading,
            CAST(
                CASE
                    WHEN b.meter_id % 25 = 0 THEN 'REJECTED'
                    WHEN b.meter_id % 20 = 0 THEN 'ANOMALOUS'
                    WHEN b.meter_id % 15 = 0 THEN 'ANOMALOUS'
                    ELSE 'ACCEPTED'
                END AS VARCHAR(10)
            ) AS status,
            CAST(
                CASE
                    WHEN b.meter_id % 25 = 0 THEN 'R2_CURRENT_LOWER_THAN_PREVIOUS'
                    WHEN b.meter_id % 20 = 0 THEN 'R3_ZERO_CONSUMPTION_STREAK'
                    WHEN b.meter_id % 15 = 0 THEN 'R4_ATYPICAL_CONSUMPTION'
                    ELSE NULL
                END AS NVARCHAR(200)
            ) AS reason,
            CAST('readings-2026-03.csv' AS NVARCHAR(260)) AS source_file
        FROM base b
    )
    INSERT INTO dbo.readings (
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
        p.meter_id,
        p.period_date,
        p.previous_reading,
        p.current_reading,
        p.status,
        p.reason,
        p.source_file,
        LOWER(CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', CONCAT(p.meter_code, '|', CONVERT(VARCHAR(10), p.period_date, 23), '|', p.current_reading, '|', p.source_file)), 2))
    FROM periods p;

    /* Seed: preinvoices for ACCEPTED and ANOMALOUS readings */
    INSERT INTO dbo.preinvoices (
        reading_id,
        meter_id,
        period_date,
        tariff_kwh,
        billable_consumption_kwh,
        subtotal,
        tax_pct,
        tax_amount,
        total_amount,
        notification_status,
        manual_review_pending,
        notification_date_utc
    )
    SELECT
        r.reading_id,
        r.meter_id,
        r.period_date,
        st.tariff_kwh,
        r.consumption_kwh,
        CAST(r.consumption_kwh * st.tariff_kwh AS DECIMAL(18,2)) AS subtotal,
        CAST(19.00 AS DECIMAL(5,2)) AS tax_pct,
        CAST((r.consumption_kwh * st.tariff_kwh) * 0.19 AS DECIMAL(18,2)) AS tax_amount,
        CAST((r.consumption_kwh * st.tariff_kwh) * 1.19 AS DECIMAL(18,2)) AS total_amount,
        CASE
            WHEN r.status = 'ANOMALOUS' THEN 'PENDING'
            WHEN r.meter_id % 11 = 0 THEN 'SENT'
            ELSE 'PENDING'
        END AS notification_status,
        CASE WHEN r.status = 'ANOMALOUS' THEN 1 ELSE 0 END AS manual_review_pending,
        CASE
            WHEN r.status = 'ANOMALOUS' THEN NULL
            WHEN r.meter_id % 11 = 0 THEN SYSUTCDATETIME()
            ELSE NULL
        END AS notification_date_utc
    FROM dbo.readings r
    INNER JOIN dbo.meters m ON m.meter_id = r.meter_id
    INNER JOIN dbo.stratum_tariffs st
        ON st.stratum_id = m.socioeconomic_stratum
       AND st.is_active = 1
    WHERE r.status IN ('ACCEPTED','ANOMALOUS');

    /* Post-seed constraints: add PK/FK/UQ/CHECK validations only after data is loaded */
    ALTER TABLE dbo.validation_thresholds
        ADD CONSTRAINT PK_validation_thresholds PRIMARY KEY (threshold_id);

    ALTER TABLE dbo.validation_thresholds
        ADD CONSTRAINT CK_thresholds_atypical_pct CHECK (atypical_consumption_pct BETWEEN 100.00 AND 10000.00);
    ALTER TABLE dbo.validation_thresholds
        ADD CONSTRAINT CK_thresholds_zero_periods CHECK (zero_consumption_periods BETWEEN 1 AND 12);
    ALTER TABLE dbo.validation_thresholds
        ADD CONSTRAINT CK_thresholds_negative_reading CHECK (negative_reading_min_kwh >= 0);
    ALTER TABLE dbo.validation_thresholds
        ADD CONSTRAINT CK_thresholds_avg_months CHECK (historical_average_months BETWEEN 1 AND 24);

    ALTER TABLE dbo.strata
        ADD CONSTRAINT PK_strata PRIMARY KEY (stratum_id);
    ALTER TABLE dbo.strata
        ADD CONSTRAINT CK_strata_id CHECK (stratum_id BETWEEN 1 AND 6);
    ALTER TABLE dbo.strata
        ADD CONSTRAINT UQ_strata_name UNIQUE (stratum_name);

    ALTER TABLE dbo.stratum_tariffs
        ADD CONSTRAINT PK_stratum_tariffs PRIMARY KEY (stratum_tariff_id);
    ALTER TABLE dbo.stratum_tariffs
        ADD CONSTRAINT FK_stratum_tariffs_strata FOREIGN KEY (stratum_id) REFERENCES dbo.strata(stratum_id);
    ALTER TABLE dbo.stratum_tariffs
        ADD CONSTRAINT UQ_stratum_tariffs_from UNIQUE (stratum_id, effective_from_date);
    ALTER TABLE dbo.stratum_tariffs
        ADD CONSTRAINT CK_stratum_tariffs_tariff CHECK (tariff_kwh > 0);
    ALTER TABLE dbo.stratum_tariffs
        ADD CONSTRAINT CK_stratum_tariffs_dates CHECK (effective_to_date IS NULL OR effective_to_date > effective_from_date);

    ALTER TABLE dbo.meters
        ADD CONSTRAINT PK_meters PRIMARY KEY (meter_id);
    ALTER TABLE dbo.meters
        ADD CONSTRAINT FK_meters_strata FOREIGN KEY (socioeconomic_stratum) REFERENCES dbo.strata(stratum_id);
    ALTER TABLE dbo.meters
        ADD CONSTRAINT UQ_meters_code UNIQUE (meter_code);
    ALTER TABLE dbo.meters
        ADD CONSTRAINT CK_meters_email CHECK (notification_email LIKE '%_@_%._%');
    ALTER TABLE dbo.meters
        ADD CONSTRAINT CK_meters_stratum CHECK (socioeconomic_stratum BETWEEN 1 AND 6);
    ALTER TABLE dbo.meters
        ADD CONSTRAINT CK_meters_zero_periods CHECK (zero_consumption_periods BETWEEN 1 AND 12);
    ALTER TABLE dbo.meters
        ADD CONSTRAINT CK_meters_threshold CHECK (increase_threshold_pct >= 100.00 AND increase_threshold_pct <= 10000.00);
    ALTER TABLE dbo.meters
        ADD CONSTRAINT CK_meters_avg_window CHECK (average_window_periods BETWEEN 1 AND 24);
    ALTER TABLE dbo.meters
        ADD CONSTRAINT CK_meters_hist_avg CHECK (historical_avg_consumption_kwh >= 0);
    ALTER TABLE dbo.meters
        ADD CONSTRAINT CK_meters_tariff CHECK (tariff_kwh > 0);

    ALTER TABLE dbo.readings
        ADD CONSTRAINT PK_readings PRIMARY KEY (reading_id);
    ALTER TABLE dbo.readings
        ADD CONSTRAINT FK_readings_meters FOREIGN KEY (meter_id) REFERENCES dbo.meters(meter_id);
    ALTER TABLE dbo.readings
        ADD CONSTRAINT UQ_readings_row_hash UNIQUE (row_hash);
    ALTER TABLE dbo.readings
        ADD CONSTRAINT UQ_readings_meter_period UNIQUE (meter_id, period_date);
    ALTER TABLE dbo.readings
        ADD CONSTRAINT CK_readings_status CHECK (status IN ('ACCEPTED','REJECTED','ANOMALOUS'));
    ALTER TABLE dbo.readings
        ADD CONSTRAINT CK_readings_reason_required CHECK (status = 'ACCEPTED' OR (reason IS NOT NULL AND LTRIM(RTRIM(reason)) <> ''));
    ALTER TABLE dbo.readings
        ADD CONSTRAINT CK_readings_rule1_consistency CHECK (status = 'REJECTED' OR current_reading >= 0);
    ALTER TABLE dbo.readings
        ADD CONSTRAINT CK_readings_rule2_consistency CHECK (status = 'REJECTED' OR current_reading >= previous_reading);

    ALTER TABLE dbo.preinvoices
        ADD CONSTRAINT PK_preinvoices PRIMARY KEY (preinvoice_id);
    ALTER TABLE dbo.preinvoices
        ADD CONSTRAINT FK_preinvoices_readings FOREIGN KEY (reading_id) REFERENCES dbo.readings(reading_id);
    ALTER TABLE dbo.preinvoices
        ADD CONSTRAINT FK_preinvoices_meters FOREIGN KEY (meter_id) REFERENCES dbo.meters(meter_id);
    ALTER TABLE dbo.preinvoices
        ADD CONSTRAINT UQ_preinvoices_reading UNIQUE (reading_id);
    ALTER TABLE dbo.preinvoices
        ADD CONSTRAINT CK_preinvoices_amounts CHECK (
            tariff_kwh > 0 AND
            billable_consumption_kwh >= 0 AND
            subtotal >= 0 AND
            tax_pct BETWEEN 0 AND 100 AND
            tax_amount >= 0 AND
            total_amount >= 0
        );
    ALTER TABLE dbo.preinvoices
        ADD CONSTRAINT CK_preinvoices_notif_status CHECK (notification_status IN ('PENDING','SENT','PAID'));
    ALTER TABLE dbo.preinvoices
        ADD CONSTRAINT CK_preinvoices_review_flag CHECK (
            (manual_review_pending = 1 AND notification_status = 'PENDING') OR
            (manual_review_pending = 0 AND notification_status IN ('PENDING','SENT','PAID'))
        );
    ALTER TABLE dbo.preinvoices
        ADD CONSTRAINT CK_preinvoices_notification_date CHECK (
            (notification_status = 'PENDING' AND notification_date_utc IS NULL) OR
            (notification_status IN ('SENT','PAID') AND notification_date_utc IS NOT NULL)
        );

    COMMIT TRANSACTION;

    /* Quick seed volume check */
    SELECT 'meters' AS table_name, COUNT(1) AS total FROM dbo.meters
    UNION ALL
    SELECT 'readings' AS table_name, COUNT(1) AS total FROM dbo.readings
    UNION ALL
    SELECT 'preinvoices' AS table_name, COUNT(1) AS total FROM dbo.preinvoices
    UNION ALL
    SELECT 'validation_thresholds' AS table_name, COUNT(1) AS total FROM dbo.validation_thresholds
    UNION ALL
    SELECT 'strata' AS table_name, COUNT(1) AS total FROM dbo.strata
    UNION ALL
    SELECT 'stratum_tariffs' AS table_name, COUNT(1) AS total FROM dbo.stratum_tariffs;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
