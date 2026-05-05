DECLARE @METER_ID INT = 10;

WITH [thresholds] AS (
	SELECT
		[atypical_consumption_pct],
		[tax_pct],
		[zero_consumption_periods],
		[negative_reading_min_kwh],
		[historical_average_months]
	FROM
		[dbo].[validation_thresholds]
	WHERE
		[is_active] = 1
), [latest_reading] AS (
	SELECT TOP (1)
		[r].[current_reading],
		[r].[consumption_kwh]
	FROM
		[dbo].[readings] AS [r]
	WHERE
		[r].[meter_id] = @METER_ID
		AND [r].[status] IN ('ACCEPTED', 'ANOMALOUS')
	ORDER BY
		[r].[period_date] DESC
)
SELECT
	[m].[meter_id],
	[m].[meter_code],
	[m].[address],
	[m].[notification_email],
	[m].[socioeconomic_stratum],
	[thresholds].*,
	[st].[tariff_kwh],
	ISNULL([latest_reading].[current_reading], 0) AS [previous_reading],
	ISNULL([latest_reading].[consumption_kwh], 0) AS [previous_consumption],
	[m].[zero_consumption_periods] AS [meter_zero_consumption_periods],
	[m].[historical_avg_consumption_kwh]
FROM
	[meters] AS [m]
CROSS JOIN
	[thresholds]
CROSS JOIN
	[latest_reading]
INNER JOIN
	[stratum_tariffs] AS [st]
	ON [st].[stratum_id] = [m].[socioeconomic_stratum]
	AND [st].[is_active] = 1
WHERE
	[m].[meter_id] = @METER_ID
	AND [m].[is_active] = 1