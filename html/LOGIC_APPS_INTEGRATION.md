# Integración SendGrid + HTML Template con Azure Logic Apps

## Arquitectura Recomendada

```
SQL Server (vw_meters_context)
         ↓
   Logic Apps (Flujo)
         ↓
[Obtener datos] → [Reemplazar variables en HTML] → [Enviar con SendGrid]
         ↓
   Azure Storage Blob (Template HTML)
```

## Opción 1: HTML en Azure Blob Storage (RECOMENDADO)

### Paso 1: Subir template.html a Azure Blob Storage

1. En Azure Portal → **Storage Accounts** → Tu cuenta de almacenamiento
2. Crea un contenedor llamado `email-templates`
3. Sube el archivo `template.html`
4. Copia la **URL del blob**

### Paso 2: Configurar el Logic App

El flujo quedaría así:

```
1. SQL Server trigger / Recurrence
   ↓
2. Execute Query (obtener datos de vw_meters_context)
   ↓
3. Get blob content (obtener template.html de Storage)
   ↓
4. Replace variables (usando acciones de composición)
   ↓
5. Send email (SendGrid connector)
```

## Opción 2: HTML como Variable en Logic App

Para templates pequeños, puedes embeber el HTML directamente en una variable del Logic App.

### Configuración del Logic App - Definición JSON

```json
{
  "definition": {
    "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
    "actions": {
      "ExecuteQuery": {
        "type": "ApiConnection",
        "inputs": {
          "host": {
            "connection": {
              "name": "@parameters('$connections')['sql']['connectionId']"
            }
          },
          "method": "post",
          "body": {
            "query": "SELECT [meter_id], [meter_code], [address], [notification_email], [socioeconomic_stratum], [tariff_kwh], [previous_reading], [previous_consumption], [historical_avg_consumption_kwh], [tax_pct] FROM [dbo].[vw_meters_context] WHERE [meter_id] = @parameters('MeterId')"
          },
          "parameters": {
            "MeterId": "@variables('MeterId')"
          }
        }
      },
      "GetBlobContent": {
        "type": "ApiConnection",
        "inputs": {
          "host": {
            "connection": {
              "name": "@parameters('$connections')['azureblob']['connectionId']"
            }
          },
          "method": "get",
          "path": "/datasets/default/files/@{encodeURIComponent('email-templates/template.html')}/content"
        }
      },
      "ReplaceVariables": {
        "type": "Compose",
        "inputs": "@{
          replace(
            replace(
              replace(
                replace(
                  replace(
                    replace(
                      replace(body('GetBlobContent'),
                        '{{meter_code}}',
                        body('ExecuteQuery')['recordsets'][0][0]['meter_code']
                      ),
                      '{{address}}',
                      body('ExecuteQuery')['recordsets'][0][0]['address']
                    ),
                    '{{notification_email}}',
                    body('ExecuteQuery')['recordsets'][0][0]['notification_email']
                  ),
                  '{{socioeconomic_stratum}}',
                  string(body('ExecuteQuery')['recordsets'][0][0]['socioeconomic_stratum'])
                ),
                '{{tariff_kwh}}',
                string(body('ExecuteQuery')['recordsets'][0][0]['tariff_kwh'])
              ),
              '{{previous_reading}}',
              string(body('ExecuteQuery')['recordsets'][0][0]['previous_reading'])
            ),
            '{{consumption_kwh}}',
            string(sub(
              body('ExecuteQuery')['recordsets'][0][0]['current_reading'],
              body('ExecuteQuery')['recordsets'][0][0]['previous_reading']
            ))
          )
        }"
      },
      "SendEmailViaSendGrid": {
        "type": "ApiConnection",
        "inputs": {
          "host": {
            "connection": {
              "name": "@parameters('$connections')['sendgrid']['connectionId']"
            }
          },
          "method": "post",
          "body": {
            "personalizations": [
              {
                "to": [
                  {
                    "email": "@body('ExecuteQuery')['recordsets'][0][0]['notification_email']"
                  }
                ]
              }
            ],
            "from": {
              "email": "facturas@epm.com.co",
              "name": "EPM - Facturas"
            },
            "subject": "@concat('Factura de Consumo - Medidor ', body('ExecuteQuery')['recordsets'][0][0]['meter_code'])",
            "content": [
              {
                "type": "text/html",
                "value": "@{outputs('ReplaceVariables')}"
              }
            ]
          }
        }
      }
    },
    "triggers": {
      "Recurrence": {
        "type": "Recurrence",
        "recurrence": {
          "frequency": "Month",
          "interval": 1,
          "schedule": {
            "monthDays": [5]
          }
        }
      }
    }
  },
  "parameters": {
    "$connections": {
      "value": {
        "sql": {
          "connectionId": "/subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.Web/connections/sql",
          "connectionName": "sql",
          "id": "/subscriptions/{subscriptionId}/providers/Microsoft.Web/locations/eastus/managedApis/sql"
        },
        "azureblob": {
          "connectionId": "/subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.Web/connections/azureblob",
          "connectionName": "azureblob",
          "id": "/subscriptions/{subscriptionId}/providers/Microsoft.Web/locations/eastus/managedApis/azureblob"
        },
        "sendgrid": {
          "connectionId": "/subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.Web/connections/sendgrid",
          "connectionName": "sendgrid",
          "id": "/subscriptions/{subscriptionId}/providers/Microsoft.Web/locations/eastus/managedApis/sendgrid"
        }
      }
    }
  }
}
```

## Opción 3: Azure Functions + Logic Apps (MÁS FLEXIBLE)

Si el reemplazo de variables es complejo, crea una **Azure Function** que procese el template:

### Función Azure (C#)

```csharp
using System.Net;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using System.Text.RegularExpressions;

namespace EPM.Email.Functions
{
    public static class ProcessBillingTemplate
    {
        [Function("ProcessBillingTemplate")]
        public static HttpResponseData Run(
            [HttpTrigger(AuthorizationLevel.Function, "post", Route = null)] HttpRequestData req)
        {
            string requestBody = System.IO.StreamReader.EndOfStream == false ? 
                new System.IO.StreamReader(req.Body).ReadToEndAsync().Result : "";

            dynamic data = Newtonsoft.Json.JsonConvert.DeserializeObject(requestBody);

            // Obtener template desde blob storage o parámetro
            string templateHtml = GetTemplate(); // o desde parámetro

            // Reemplazar variables
            templateHtml = ReplaceVariables(templateHtml, data);

            var response = req.CreateResponse(HttpStatusCode.OK);
            response.Headers.Add("Content-Type", "application/json");
            response.WriteString(Newtonsoft.Json.JsonConvert.SerializeObject(new { 
                html = templateHtml,
                success = true 
            }));

            return response;
        }

        private static string ReplaceVariables(string html, dynamic data)
        {
            html = Regex.Replace(html, @"{{(\w+)}}", m => 
                GetPropertyValue(data, m.Groups[1].Value)?.ToString() ?? "");

            // Manejo de condicionales
            if (data["has_anomaly"] == true)
            {
                html = html.Replace("{{#if_anomaly}}", "");
                html = html.Replace("{{/if_anomaly}}", "");
            }
            else
            {
                html = Regex.Replace(html, @"{{#if_anomaly}}.*?{{/if_anomaly}}", "", RegexOptions.Singleline);
            }

            return html;
        }

        private static object GetPropertyValue(dynamic obj, string propertyName)
        {
            try
            {
                return ((System.Collections.Generic.Dictionary<string, object>)obj)[propertyName];
            }
            catch
            {
                return null;
            }
        }

        private static string GetTemplate()
        {
            // Leer desde blob storage o configuración
            return System.IO.File.ReadAllText("path/to/template.html");
        }
    }
}
```

### Llamar desde Logic Apps

```json
{
  "type": "Function",
  "inputs": {
    "function": {
      "id": "/subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.Web/sites/{functionAppName}/functions/ProcessBillingTemplate"
    },
    "method": "POST",
    "body": {
      "meter_code": "@body('ExecuteQuery')['recordsets'][0][0]['meter_code']",
      "address": "@body('ExecuteQuery')['recordsets'][0][0]['address']",
      "consumption_kwh": "@body('ExecuteQuery')['recordsets'][0][0]['consumption_kwh']",
      "has_anomaly": "@body('ExecuteQuery')['recordsets'][0][0]['has_anomaly']"
    }
  }
}
```

## Opción 4: HTML como parámetro en Logic App

Puedes almacenar el HTML como un parámetro de configuración en **Azure Key Vault**:

```json
{
  "type": "ApiConnection",
  "inputs": {
    "host": {
      "connection": {
        "name": "@parameters('$connections')['keyvault']['connectionId']"
      }
    },
    "method": "get",
    "path": "/secrets/@{encodeURIComponent('email-template-html')}/value"
  }
}
```

---

## Comparativa de Opciones

| Opción | Ventajas | Desventajas |
|--------|----------|-------------|
| **Blob Storage** | Fácil mantenimiento, separación de concerns | Requiere contenedor configurado |
| **Variable en Logic App** | Rápido, sin dependencias | Limitado para templates grandes |
| **Azure Functions** | Muy flexible, procesamiento complejo | Costo adicional, mayor complejidad |
| **Key Vault** | Seguro, centralizado | Overhead de configuración |

**RECOMENDACIÓN:** Blob Storage + Logic App (Opción 1) - Es el balance perfecto entre simplicidad y flexibilidad.

---

## Configuración del Conector SendGrid en Logic Apps

1. En Logic Apps → **+Add action**
2. Busca **SendGrid** → **Send email**
3. Auténtica con tu API Key de SendGrid
4. Configura:
   - **To:** Email del cliente
   - **From:** facturas@epm.com.co
   - **Subject:** Factura de Consumo - Medidor {{meter_code}}
   - **Body (HTML):** Resultado del reemplazo de variables

---

## Variables SQL a Reemplazar en Logic App

Basado en tu `vw_meters_context`, estas variables están disponibles:

```
{{meter_id}}
{{meter_code}}
{{address}}
{{notification_email}}
{{socioeconomic_stratum}}
{{tariff_kwh}}
{{previous_reading}}
{{previous_consumption}}
{{historical_avg_consumption_kwh}}
{{tax_pct}}
```

Y las calculadas:
```
{{consumption_kwh}} = current_reading - previous_reading
{{energy_cost}} = consumption_kwh * tariff_kwh
{{tax_amount}} = energy_cost * tax_pct / 100
{{total_amount}} = energy_cost + tax_amount
```

---

## Próximos Pasos

1. **Elige una opción** (recomiendo Blob Storage)
2. **Configura los conectores** en Logic Apps (SQL, Azure Blob, SendGrid)
3. **Prueba con un medidor específico** antes de automatizar
4. **Configura el trigger** (Recurrence mensual o SQL change tracking)

¿Quieres que te ayude a configurar el Logic App específicamente? Puedo crear el JSON completo listo para usar.
