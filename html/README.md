# Template de Factura HTML para SendGrid - EPM

## Descripción
Template HTML completo para envío de facturas de consumo de energía a través de SendGrid. Incluye CSS incrustado, es responsive y compatible con todos los clientes de correo.

## Variables Disponibles (Placeholder)

Las siguientes variables deben reemplazarse con datos reales. Usa el formato `{{variable}}`:

### Información del Cliente
- `{{meter_code}}` - Código del medidor (ej: "1002345678")
- `{{address}}` - Dirección del cliente (ej: "Calle 50 #25-30, Pereira")
- `{{socioeconomic_stratum}}` - Estrato socioeconómico (1-6)
- `{{notification_email}}` - Correo del cliente

### Fechas
- `{{billing_period}}` - Período de facturación (ej: "01 de Octubre - 31 de Octubre 2025")
- `{{issue_date}}` - Fecha de emisión (ej: "05 de Noviembre de 2025")
- `{{due_date}}` - Fecha de vencimiento (ej: "20 de Noviembre de 2025")

### Lecturas y Consumo
- `{{previous_reading}}` - Lectura anterior (kWh)
- `{{current_reading}}` - Lectura actual (kWh)
- `{{consumption_kwh}}` - Consumo del período en kWh
- `{{daily_average}}` - Promedio diario de este período
- `{{historical_avg_consumption_kwh}}` - Promedio histórico de consumo
- `{{historical_daily_average}}` - Promedio diario histórico
- `{{historical_average_months}}` - Número de meses de promedio

### Tarifas y Cálculos
- `{{tariff_kwh}}` - Tarifa por kWh (formato: 1250.50)
- `{{energy_cost}}` - Costo total de energía
- `{{tax_pct}}` - Porcentaje de impuesto (ej: 8)
- `{{tax_amount}}` - Monto del impuesto
- `{{adjustments}}` - Ajustes o cargos adicionales
- `{{total_amount}}` - Total a pagar (en formato de moneda local)

### Comparativa
- `{{consumption_variance}}` - Variación de consumo en % respecto al promedio
- `{{cost_variance}}` - Variación de costo en % respecto al promedio
- `{{historical_avg_cost}}` - Costo promedio histórico

### Anomalías (Condicionales)
- `{{#if_anomaly}}...{{/if_anomaly}}` - Sección condicional si hay consumo anómalo
  - `{{anomaly_type}}` - Tipo de anomalía (ej: "ALTO", "BAJO", "NEGATIVO")
  - `{{anomaly_percentage}}` - Porcentaje de variación
- `{{#if_zero_consumption}}...{{/if_zero_consumption}}` - Sección condicional si consumo es cero

## Colores Utilizados
- **Primary (Verde):** `#0d9648` - Headers, acciones principales
- **Secondary (Verde Claro):** `#9fcf67` - Acentos, bordes
- **Gray:** `#a1a1a5` - Textos secundarios, etiquetas
- **White:** `#fff` - Fondos principales
- **Black:** `#000` - Texto principal

## Características del Template

✅ **Responsive** - Se adapta a móviles, tablets y desktop  
✅ **CSS Incrustado** - Sin dependencias externas  
✅ **Compatible con Clientes de Correo** - Probado en Gmail, Outlook, Apple Mail  
✅ **Logo Embebido** - Usa `cid:logo.png` para incrustar imagen  
✅ **Formato de Factura Profesional** - Estructura clara y legible  
✅ **Condicionales** - Secciones que se muestran/ocultan según datos  
✅ **Accesibilidad** - Semántica HTML correcta  

## Cómo Usar con SendGrid

### Opción 1: SendGrid Web Interface
1. Ve a **Email API → Dynamic Templates**
2. Click en **Create Template**
3. Agrega una nueva versión (Blank)
4. En el editor HTML, pega el contenido del archivo `template.html`
5. En **Subject**, configura: `Factura de Consumo - Medidor {{meter_code}} - {{billing_period}}`
6. Reemplaza `cid:logo.png` con la URL de tu logo o usa Content-ID para incrustarlo

### Opción 2: Usando SendGrid C# SDK

```csharp
using SendGrid;
using SendGrid.Helpers.Mail;

var client = new SendGridClient("tu-api-key");

var from = new EmailAddress("facturas@epm.com.co", "EPM - Facturas");
var to = new EmailAddress(customerEmail);
var subject = $"Factura de Consumo - Medidor {meterCode} - {billingPeriod}";

// Cargar el template HTML
string htmlContent = File.ReadAllText("path/to/template.html");

// Reemplazar variables
htmlContent = htmlContent
    .Replace("{{meter_code}}", meterCode)
    .Replace("{{address}}", address)
    .Replace("{{socioeconomic_stratum}}", stratum.ToString())
    .Replace("{{billing_period}}", billingPeriod)
    .Replace("{{issue_date}}", issueDate)
    .Replace("{{due_date}}", dueDate)
    .Replace("{{previous_reading}}", previousReading.ToString("F2"))
    .Replace("{{current_reading}}", currentReading.ToString("F2"))
    .Replace("{{consumption_kwh}}", consumption.ToString("F2"))
    .Replace("{{daily_average}}", dailyAverage.ToString("F2"))
    .Replace("{{historical_avg_consumption_kwh}}", historicalAvg.ToString("F2"))
    .Replace("{{historical_daily_average}}", historicalDailyAvg.ToString("F2"))
    .Replace("{{historical_average_months}}", months.ToString())
    .Replace("{{tariff_kwh}}", tariff.ToString("F2"))
    .Replace("{{energy_cost}}", energyCost.ToString("F2"))
    .Replace("{{tax_pct}}", taxPercent.ToString("F2"))
    .Replace("{{tax_amount}}", taxAmount.ToString("F2"))
    .Replace("{{adjustments}}", adjustments.ToString("F2"))
    .Replace("{{total_amount}}", totalAmount.ToString("F2"))
    .Replace("{{consumption_variance}}", variancePercent.ToString("F2"))
    .Replace("{{cost_variance}}", costVariance.ToString("F2"))
    .Replace("{{historical_avg_cost}}", historicalAvgCost.ToString("F2"));

// Manejar anomalías
if (hasAnomaly)
{
    htmlContent = htmlContent
        .Replace("{{#if_anomaly}}", "")
        .Replace("{{/if_anomaly}}", "")
        .Replace("{{anomaly_type}}", anomalyType)
        .Replace("{{anomaly_percentage}}", anomalyPercent.ToString("F2"));
}
else
{
    // Remover sección de anomalía
    htmlContent = System.Text.RegularExpressions.Regex.Replace(
        htmlContent,
        @"{{#if_anomaly}}.*?{{/if_anomaly}}",
        "",
        System.Text.RegularExpressions.RegexOptions.Singleline
    );
}

// Similar para zero_consumption
if (consumption == 0)
{
    htmlContent = htmlContent
        .Replace("{{#if_zero_consumption}}", "")
        .Replace("{{/if_zero_consumption}}", "");
}
else
{
    htmlContent = System.Text.RegularExpressions.Regex.Replace(
        htmlContent,
        @"{{#if_zero_consumption}}.*?{{/if_zero_consumption}}",
        "",
        System.Text.RegularExpressions.RegexOptions.Singleline
    );
}

var mail = new SendGridMessage()
{
    From = from,
    Subject = subject,
    HtmlContent = htmlContent
};
mail.AddTo(to);

// Adjuntar logo si es necesario
// var logoBytes = File.ReadAllBytes("path/to/logo.png");
// mail.AddAttachment("logo.png", Convert.ToBase64String(logoBytes), "image/png", "inline", "logo.png");

var response = await client.SendEmailAsync(mail);
```

### Opción 3: SendGrid Templates API (Recomendado)
Usa la feature de **Substitution Tags** de SendGrid para variables dinámicas:

```json
{
  "personalizations": [
    {
      "to": [
        {
          "email": "customer@example.com"
        }
      ],
      "dynamic_template_data": {
        "meter_code": "1002345678",
        "address": "Calle 50 #25-30",
        "socioeconomic_stratum": 3,
        "billing_period": "Oct 2025",
        "issue_date": "Nov 5, 2025",
        "due_date": "Nov 20, 2025",
        "previous_reading": 45320.50,
        "current_reading": 45680.75,
        "consumption_kwh": 360.25,
        "daily_average": 12.01,
        "historical_avg_consumption_kwh": 350,
        "historical_daily_average": 11.67,
        "historical_average_months": 12,
        "tariff_kwh": 1250.50,
        "energy_cost": 450312.50,
        "tax_pct": 8,
        "tax_amount": 36024.00,
        "adjustments": 0,
        "total_amount": 486336.50,
        "consumption_variance": 2.93,
        "cost_variance": 2.93,
        "historical_avg_cost": 437500,
        "has_anomaly": false,
        "has_zero_consumption": false
      }
    }
  ],
  "from": {
    "email": "facturas@epm.com.co",
    "name": "EPM - Facturas"
  },
  "template_id": "d-xxxxxxxxxxxxxxxxxxxxx"
}
```

## Customización

### Cambiar Colores
Busca en el CSS las siguientes secciones:
- `#0d9648` → Color primario (verde oscuro)
- `#9fcf67` → Color secundario (verde claro)
- `#a1a1a5` → Gris
- `#fff` → Blanco
- `#000` → Negro

### Agregar Logo
El template espera un logo en formato:
```html
<img src="cid:logo.png" alt="EPM" class="logo">
```

Para SendGrid, reemplaza con la URL del logo:
```html
<img src="https://tu-cdn.com/logo.png" alt="EPM" class="logo">
```

### Ajustar Ancho
La sección `.container` está configurada con `max-width: 800px`. Puedes cambiarla según necesidad.

## Testing
Recomendamos probar el template en:
- [Litmus](https://www.litmus.com/) - Testing de emails
- [Email on Acid](https://www.emailonacid.com/) - Compatibilidad multi-cliente
- Gmail Web, Gmail Mobile, Outlook Desktop, iPhone Mail

## Notas Importantes
⚠️ **CSS Incrustado:** Todo el CSS está dentro de `<style>` en el `<head>`. SendGrid soporta esto nativamente.

⚠️ **Imágenes:** Usa URLs HTTPS completas o Content-ID de SendGrid para embeber imágenes.

⚠️ **Links:** Los links se pueden rastrear automáticamente con SendGrid usando su feature de Click Tracking.

⚠️ **Fuentes:** El template usa fuentes seguras del sistema. Si necesitas fuentes personalizadas, usa @import de Google Fonts (compatibilidad limitada en algunos clientes).

---

**Creado para:** Integración EPM - SendGrid  
**Última actualización:** 2025-11-05  
**Versión:** 1.0
