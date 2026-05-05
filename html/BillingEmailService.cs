using System;
using System.Data;
using System.IO;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using SendGrid;
using SendGrid.Helpers.Mail;
using Microsoft.Data.SqlClient;

namespace EPM.Email.Service
{
    /// <summary>
    /// ⚠️ NOTA: Este servicio NO se usa si estás usando Azure Logic Apps.
    /// 
    /// Si usas Logic Apps (RECOMENDADO):
    ///   - Mira: /logic-apps/SETUP_GUIDE.md
    ///   - Usa el flujo: /logic-apps/billing-email-workflow.json
    ///   - Template: /html/template.html en Azure Blob Storage
    /// 
    /// Si usas un backend C# tradicional (API REST, Workers, etc.):
    ///   - Entonces sí usa esta clase BillingEmailService
    ///   - Registra en DI: services.AddScoped<BillingEmailService>()
    ///   - Inyecta en controlador o servicio
    /// 
    /// Servicio para envío de facturas de consumo a través de SendGrid
    /// Integración con SQL Server (vista vw_meters_context)
    /// </summary>
    public class BillingEmailService
    {
        private readonly SendGridClient _sendGridClient;
        private readonly string _sqlConnectionString;
        private readonly string _templatePath;
        private readonly string _logoUrl;

        public BillingEmailService(
            string sendGridApiKey,
            string sqlConnectionString,
            string templatePath,
            string logoUrl = "https://tu-cdn.com/logo.png")
        {
            _sendGridClient = new SendGridClient(sendGridApiKey);
            _sqlConnectionString = sqlConnectionString;
            _templatePath = templatePath;
            _logoUrl = logoUrl;
        }

        /// <summary>
        /// Obtiene datos de facturación desde la vista vw_meters_context
        /// </summary>
        public async Task<BillingData> GetBillingDataAsync(int meterId, string periodDate)
        {
            using (var connection = new SqlConnection(_sqlConnectionString))
            {
                await connection.OpenAsync();

                using (var command = new SqlCommand("sp_GetMeterBillingData", connection))
                {
                    command.CommandType = CommandType.StoredProcedure;
                    command.Parameters.AddWithValue("@METER_ID", meterId);
                    command.Parameters.AddWithValue("@PERIOD_DATE", periodDate);

                    using (var reader = await command.ExecuteReaderAsync())
                    {
                        if (await reader.ReadAsync())
                        {
                            return new BillingData
                            {
                                MeterId = Convert.ToInt32(reader["meter_id"]),
                                MeterCode = reader["meter_code"].ToString(),
                                Address = reader["address"].ToString(),
                                NotificationEmail = reader["notification_email"].ToString(),
                                SocioeconomicStratum = Convert.ToInt32(reader["socioeconomic_stratum"]),
                                TariffKwh = Convert.ToDecimal(reader["tariff_kwh"]),
                                PreviousReading = Convert.ToDecimal(reader["previous_reading"]),
                                PreviousConsumption = Convert.ToDecimal(reader["previous_consumption"]),
                                HistoricalAvgConsumption = Convert.ToDecimal(reader["historical_avg_consumption_kwh"]),
                                TaxPercent = Convert.ToDecimal(reader["tax_pct"])
                            };
                        }
                    }
                }
            }

            return null;
        }

        /// <summary>
        /// Obtiene datos de la lectura actual del medidor
        /// </summary>
        public async Task<ReadingData> GetCurrentReadingAsync(int meterId)
        {
            using (var connection = new SqlConnection(_sqlConnectionString))
            {
                await connection.OpenAsync();

                const string query = @"
                    SELECT TOP 1
                        [r].[current_reading],
                        [r].[consumption_kwh],
                        [r].[status],
                        [r].[period_date]
                    FROM [dbo].[readings] AS [r]
                    WHERE [r].[meter_id] = @METER_ID
                        AND [r].[status] IN ('ACCEPTED', 'ANOMALOUS')
                    ORDER BY [r].[period_date] DESC";

                using (var command = new SqlCommand(query, connection))
                {
                    command.Parameters.AddWithValue("@METER_ID", meterId);

                    using (var reader = await command.ExecuteReaderAsync())
                    {
                        if (await reader.ReadAsync())
                        {
                            return new ReadingData
                            {
                                CurrentReading = Convert.ToDecimal(reader["current_reading"]),
                                ConsumptionKwh = Convert.ToDecimal(reader["consumption_kwh"]),
                                Status = reader["status"].ToString(),
                                PeriodDate = Convert.ToDateTime(reader["period_date"])
                            };
                        }
                    }
                }
            }

            return null;
        }

        /// <summary>
        /// Enriquece los datos de facturación con información de consumo y anomalías
        /// </summary>
        public BillingEmailData EnrichBillingData(BillingData billing, ReadingData reading)
        {
            var consumption = reading.ConsumptionKwh;
            var energyCost = consumption * billing.TariffKwh;
            var taxAmount = energyCost * (billing.TaxPercent / 100m);
            var totalAmount = energyCost + taxAmount;

            // Calcular varianza
            decimal consumptionVariance = 0;
            if (billing.HistoricalAvgConsumption > 0)
            {
                consumptionVariance = ((consumption - billing.HistoricalAvgConsumption) 
                    / billing.HistoricalAvgConsumption) * 100m;
            }

            // Detectar anomalías
            var hasAnomaly = false;
            var anomalyType = "";

            if (reading.Status == "ANOMALOUS")
            {
                hasAnomaly = true;
                if (consumption > billing.HistoricalAvgConsumption)
                    anomalyType = "ALTO";
                else if (consumption < (billing.HistoricalAvgConsumption * 0.5m))
                    anomalyType = "BAJO";
            }

            var hasZeroConsumption = consumption == 0;

            return new BillingEmailData
            {
                MeterCode = billing.MeterCode,
                Address = billing.Address,
                NotificationEmail = billing.NotificationEmail,
                SocioeconomicStratum = billing.SocioeconomicStratum,
                BillingPeriod = GetBillingPeriod(reading.PeriodDate),
                IssueDate = DateTime.Now.ToLongDateString(),
                DueDate = DateTime.Now.AddDays(15).ToLongDateString(),
                PreviousReading = billing.PreviousReading.ToString("F2"),
                CurrentReading = reading.CurrentReading.ToString("F2"),
                ConsumptionKwh = consumption.ToString("F2"),
                DailyAverage = (consumption / 30m).ToString("F2"),
                HistoricalAvgConsumption = billing.HistoricalAvgConsumption.ToString("F2"),
                HistoricalDailyAverage = (billing.HistoricalAvgConsumption / 30m).ToString("F2"),
                HistoricalAverageMonths = 12,
                TariffKwh = billing.TariffKwh.ToString("F2"),
                EnergyCost = energyCost.ToString("F2"),
                TaxPct = billing.TaxPercent.ToString("F2"),
                TaxAmount = taxAmount.ToString("F2"),
                Adjustments = "0.00",
                TotalAmount = totalAmount.ToString("F2"),
                ConsumptionVariance = consumptionVariance.ToString("F2"),
                CostVariance = consumptionVariance.ToString("F2"),
                HistoricalAvgCost = (billing.HistoricalAvgConsumption * billing.TariffKwh).ToString("F2"),
                HasAnomaly = hasAnomaly,
                AnomalyType = anomalyType,
                AnomalyPercentage = Math.Abs(consumptionVariance).ToString("F2"),
                HasZeroConsumption = hasZeroConsumption
            };
        }

        /// <summary>
        /// Envía el correo de factura
        /// </summary>
        public async Task<Response> SendBillingEmailAsync(BillingEmailData data)
        {
            try
            {
                // Cargar template HTML
                var htmlContent = File.ReadAllText(_templatePath);

                // Reemplazar variables
                htmlContent = ReplaceVariables(htmlContent, data);

                // Crear mensaje
                var from = new EmailAddress("facturas@epm.com.co", "EPM - Facturas");
                var to = new EmailAddress(data.NotificationEmail);
                var subject = $"Factura de Consumo - Medidor {data.MeterCode} - {data.BillingPeriod}";

                var mail = new SendGridMessage()
                {
                    From = from,
                    Subject = subject,
                    HtmlContent = htmlContent
                };

                mail.AddTo(to);

                // Opcional: agregar ReplyTo
                mail.ReplyToList.Add(new EmailAddress("soporte@epm.com.co", "Soporte EPM"));

                // Opcional: agregar tracking
                mail.TrackingSettings = new TrackingSettings
                {
                    ClickTracking = new ClickTracking { Enabled = true },
                    OpenTracking = new OpenTracking { Enabled = true }
                };

                // Enviar
                var response = await _sendGridClient.SendEmailAsync(mail);
                return response;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error enviando correo: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// Reemplaza variables en el template HTML
        /// </summary>
        private string ReplaceVariables(string html, BillingEmailData data)
        {
            html = html.Replace("{{meter_code}}", data.MeterCode);
            html = html.Replace("{{address}}", data.Address);
            html = html.Replace("{{socioeconomic_stratum}}", data.SocioeconomicStratum.ToString());
            html = html.Replace("{{billing_period}}", data.BillingPeriod);
            html = html.Replace("{{issue_date}}", data.IssueDate);
            html = html.Replace("{{due_date}}", data.DueDate);
            html = html.Replace("{{previous_reading}}", data.PreviousReading);
            html = html.Replace("{{current_reading}}", data.CurrentReading);
            html = html.Replace("{{consumption_kwh}}", data.ConsumptionKwh);
            html = html.Replace("{{daily_average}}", data.DailyAverage);
            html = html.Replace("{{historical_avg_consumption_kwh}}", data.HistoricalAvgConsumption);
            html = html.Replace("{{historical_daily_average}}", data.HistoricalDailyAverage);
            html = html.Replace("{{historical_average_months}}", data.HistoricalAverageMonths.ToString());
            html = html.Replace("{{tariff_kwh}}", data.TariffKwh);
            html = html.Replace("{{energy_cost}}", data.EnergyCost);
            html = html.Replace("{{tax_pct}}", data.TaxPct);
            html = html.Replace("{{tax_amount}}", data.TaxAmount);
            html = html.Replace("{{adjustments}}", data.Adjustments);
            html = html.Replace("{{total_amount}}", data.TotalAmount);
            html = html.Replace("{{consumption_variance}}", data.ConsumptionVariance);
            html = html.Replace("{{cost_variance}}", data.CostVariance);
            html = html.Replace("{{historical_avg_cost}}", data.HistoricalAvgCost);

            // Manejo de condicionales
            if (data.HasAnomaly)
            {
                html = html.Replace("{{#if_anomaly}}", "");
                html = html.Replace("{{/if_anomaly}}", "");
                html = html.Replace("{{anomaly_type}}", data.AnomalyType);
                html = html.Replace("{{anomaly_percentage}}", data.AnomalyPercentage);
            }
            else
            {
                html = Regex.Replace(html, @"{{#if_anomaly}}.*?{{/if_anomaly}}", "", RegexOptions.Singleline);
            }

            if (data.HasZeroConsumption)
            {
                html = html.Replace("{{#if_zero_consumption}}", "");
                html = html.Replace("{{/if_zero_consumption}}", "");
            }
            else
            {
                html = Regex.Replace(html, @"{{#if_zero_consumption}}.*?{{/if_zero_consumption}}", "", RegexOptions.Singleline);
            }

            return html;
        }

        private string GetBillingPeriod(DateTime periodDate)
        {
            var firstDay = new DateTime(periodDate.Year, periodDate.Month, 1);
            var lastDay = firstDay.AddMonths(1).AddDays(-1);

            return $"01 de {GetMonthName(firstDay.Month)} - {lastDay.Day} de {GetMonthName(lastDay.Month)} {lastDay.Year}";
        }

        private string GetMonthName(int month)
        {
            var months = new[] { "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
                                "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre" };
            return months[month - 1];
        }
    }

    // ===== MODELOS DE DATOS =====

    public class BillingData
    {
        public int MeterId { get; set; }
        public string MeterCode { get; set; }
        public string Address { get; set; }
        public string NotificationEmail { get; set; }
        public int SocioeconomicStratum { get; set; }
        public decimal TariffKwh { get; set; }
        public decimal PreviousReading { get; set; }
        public decimal PreviousConsumption { get; set; }
        public decimal HistoricalAvgConsumption { get; set; }
        public decimal TaxPercent { get; set; }
    }

    public class ReadingData
    {
        public decimal CurrentReading { get; set; }
        public decimal ConsumptionKwh { get; set; }
        public string Status { get; set; }
        public DateTime PeriodDate { get; set; }
    }

    public class BillingEmailData
    {
        public string MeterCode { get; set; }
        public string Address { get; set; }
        public string NotificationEmail { get; set; }
        public int SocioeconomicStratum { get; set; }
        public string BillingPeriod { get; set; }
        public string IssueDate { get; set; }
        public string DueDate { get; set; }
        public string PreviousReading { get; set; }
        public string CurrentReading { get; set; }
        public string ConsumptionKwh { get; set; }
        public string DailyAverage { get; set; }
        public string HistoricalAvgConsumption { get; set; }
        public string HistoricalDailyAverage { get; set; }
        public int HistoricalAverageMonths { get; set; }
        public string TariffKwh { get; set; }
        public string EnergyCost { get; set; }
        public string TaxPct { get; set; }
        public string TaxAmount { get; set; }
        public string Adjustments { get; set; }
        public string TotalAmount { get; set; }
        public string ConsumptionVariance { get; set; }
        public string CostVariance { get; set; }
        public string HistoricalAvgCost { get; set; }
        public bool HasAnomaly { get; set; }
        public string AnomalyType { get; set; }
        public string AnomalyPercentage { get; set; }
        public bool HasZeroConsumption { get; set; }
    }

    // ===== USO DESDE OTRA CLASE =====
    /*
    
    public class BillingProcessor
    {
        public async Task SendBillingNotificationsAsync()
        {
            var service = new BillingEmailService(
                sendGridApiKey: "SG.xxxxxxxxxxxxxxxxxxxxx",
                sqlConnectionString: "Server=.;Database=EPM;...",
                templatePath: @"C:\path\to\html\template.html"
            );

            // Procesar todas las facturas del período
            var meters = await GetMetersToInvoiceAsync();

            foreach (var meter in meters)
            {
                // Obtener datos de facturación
                var billingData = await service.GetBillingDataAsync(meter.MeterId, DateTime.Now.ToString("yyyy-MM-dd"));
                var readingData = await service.GetCurrentReadingAsync(meter.MeterId);

                if (billingData != null && readingData != null)
                {
                    // Enriquecer datos
                    var emailData = service.EnrichBillingData(billingData, readingData);

                    // Enviar correo
                    var response = await service.SendBillingEmailAsync(emailData);

                    if (response.StatusCode == System.Net.HttpStatusCode.Accepted)
                    {
                        Console.WriteLine($"Factura enviada a {emailData.NotificationEmail}");
                    }
                    else
                    {
                        Console.WriteLine($"Error enviando factura: {response.StatusCode}");
                    }
                }
            }
        }
    }
    
    */
}
