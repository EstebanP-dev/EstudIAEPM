# Configuración del Logic App para Envío de Facturas con SendGrid

## 📋 Checklist de Configuración Previas

- [ ] Azure Storage Account creada
- [ ] Contenedor `email-templates` creado en Blob Storage
- [ ] Archivo `template.html` subido al contenedor
- [ ] SendGrid API Key disponible
- [ ] SQL Server accesible desde Azure (Firewall configurado)
- [ ] Credenciales SQL Server disponibles

---

## ✅ Paso a Paso: Configuración del Logic App

### 1. Crear el Logic App en Azure Portal

1. Ve a **Azure Portal** → **Create a resource**
2. Busca **Logic App** → Click en **Create**
3. Configura:
   - **Subscription:** Tu suscripción
   - **Resource group:** Tu grupo de recursos
   - **Logic App name:** `EPM-BillingEmailWorkflow`
   - **Region:** Misma región de tus otros recursos
   - **Plan type:** Consumption (más económico)
4. Click en **Create**

### 2. Abrir el Diseñador de Logic Apps

1. Una vez creado, ve a **Resource** → **Logic app designer**
2. Selecciona **Blank Logic App**

### 3. Agregar el Trigger (Recurrencia Mensual)

1. En el diseñador, busca **Schedule - Recurrence**
2. Configura:
   - **Frequency:** Month
   - **Interval:** 1
   - **On these days:** Selecciona "5" (día 5 de cada mes)
   - **At these hours:** 02:00 (2 AM UTC)
   - **At these minutes:** 00

### 4. Crear Conexión a SQL Server

1. Click en **+New step**
2. Busca **SQL Server** → **Execute a query**
3. Click en **Create new connection**
4. Configura:
   - **Connection name:** `EPMSQLConnection`
   - **Authentication type:** SQL Server Authentication
   - **Server:** Tu servidor SQL (ej: `epmserver.database.windows.net`)
   - **Database:** `EPM` (tu base de datos)
   - **Username:** Tu usuario SQL
   - **Password:** Tu contraseña SQL
5. Click en **Create**

### 5. Configurar la Acción de Obtención de Datos (GetMetersFromSQL)

1. En la acción **Execute a query (SQL)**, pegue esta query:

```sql
SELECT DISTINCT
    [m].[meter_id],
    [m].[meter_code],
    [m].[address],
    [m].[notification_email],
    [m].[socioeconomic_stratum],
    [st].[tariff_kwh],
    ISNULL([r].[current_reading], 0) AS [current_reading],
    ISNULL([r].[previous_reading], 0) AS [previous_reading],
    [m].[historical_avg_consumption_kwh],
    [th].[tax_pct]
FROM [dbo].[meters] AS [m]
LEFT JOIN [dbo].[stratum_tariffs] AS [st]
    ON [st].[stratum_id] = [m].[socioeconomic_stratum]
    AND [st].[is_active] = 1
LEFT JOIN (
    SELECT TOP 1 [meter_id], [current_reading], [previous_reading], [status], [period_date]
    FROM [dbo].[readings]
    ORDER BY [period_date] DESC
) AS [r]
    ON [r].[meter_id] = [m].[meter_id]
LEFT JOIN [dbo].[validation_thresholds] AS [th]
    ON [th].[is_active] = 1
WHERE [m].[is_active] = 1
AND [m].[notification_email] IS NOT NULL
```

### 6. Agregar Loop (ForEach) para Procesar cada Medidor

1. Click en **+New step**
2. Busca **Control** → **For each**
3. En **Select an output from previous steps**, selecciona: `recordsets[0]` (del paso SQL)

### 7. Dentro del Loop: Obtener Template HTML de Blob Storage

1. Click en **Add an action** (dentro del loop)
2. Busca **Azure Blob Storage** → **Get blob content (path)**
3. Configura:
   - **Connection:** Crea nueva conexión a Azure Storage
   - **Storage Account:** Tu storage account
   - **Path:** `/email-templates/template.html`

### 8. Dentro del Loop: Calcular Valores

Agrega múltiples acciones **Compose** para calcular:

#### a) Calcular Consumo
```
Compose - Calcular Consumo
Name: CalculateConsumption
Expression: @sub(items('ForEachMeter')['current_reading'], items('ForEachMeter')['previous_reading'])
```

#### b) Calcular Costo de Energía
```
Compose - Costo Energía
Name: CalculateEnergyCost
Expression: @mul(outputs('CalculateConsumption'), items('ForEachMeter')['tariff_kwh'])
```

#### c) Calcular Impuesto
```
Compose - Costo Impuesto
Name: CalculateTaxAmount
Expression: @mul(outputs('CalculateEnergyCost'), div(items('ForEachMeter')['tax_pct'], 100))
```

#### d) Calcular Total
```
Compose - Total
Name: CalculateTotalAmount
Expression: @add(outputs('CalculateEnergyCost'), outputs('CalculateTaxAmount'))
```

#### e) Calcular Varianza
```
Compose - Varianza Consumo
Name: CalculateConsumptionVariance
Expression: @if(equals(items('ForEachMeter')['historical_avg_consumption_kwh'], 0), 0, mul(div(sub(outputs('CalculateConsumption'), items('ForEachMeter')['historical_avg_consumption_kwh']), items('ForEachMeter')['historical_avg_consumption_kwh']), 100))
```

#### f) Detectar Anomalía
```
Compose - Detectar Anomalía
Name: DetectAnomaly
Expression: @if(equals(outputs('CalculateConsumption'), 0), 'CERO', if(greaterOrEquals(outputs('CalculateConsumptionVariance'), 30), 'ALTO', if(lessOrEquals(outputs('CalculateConsumptionVariance'), -50), 'BAJO', 'NORMAL')))
```

### 9. Reemplazar Variables en Template

1. Agrega una acción **Compose** con nombre `ReplaceVariablesInTemplate`
2. En el campo de expresión, copia esta expresión compleja:

```
@replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(
body('GetBlobContent'),
'{{meter_code}}',
items('ForEachMeter')['meter_code']),
'{{address}}',
items('ForEachMeter')['address']),
'{{socioeconomic_stratum}}',
string(items('ForEachMeter')['socioeconomic_stratum'])),
'{{notification_email}}',
items('ForEachMeter')['notification_email']),
'{{billing_period}}',
concat('01 de ', formatDateTime(utcNow(), 'MMMM'), ' - ', string(day(addDays(startOfMonth(utcNow()), 32))), ' de ', formatDateTime(utcNow(), 'MMMM yyyy'))),
'{{issue_date}}',
formatDateTime(utcNow(), 'dd de MMMM de yyyy')),
'{{due_date}}',
formatDateTime(addDays(utcNow(), 15), 'dd de MMMM de yyyy')),
'{{previous_reading}}',
string(items('ForEachMeter')['previous_reading'])),
'{{current_reading}}',
string(items('ForEachMeter')['current_reading'])),
'{{consumption_kwh}}',
string(outputs('CalculateConsumption'))),
'{{daily_average}}',
string(div(outputs('CalculateConsumption'), 30))),
'{{historical_avg_consumption_kwh}}',
string(items('ForEachMeter')['historical_avg_consumption_kwh'])),
'{{historical_daily_average}}',
string(div(items('ForEachMeter')['historical_avg_consumption_kwh'], 30))),
'{{historical_average_months}}',
'12'),
'{{tariff_kwh}}',
string(items('ForEachMeter')['tariff_kwh'])),
'{{energy_cost}}',
string(outputs('CalculateEnergyCost'))),
'{{tax_pct}}',
string(items('ForEachMeter')['tax_pct'])),
'{{tax_amount}}',
string(outputs('CalculateTaxAmount'))),
'{{adjustments}}',
'0.00'),
'{{total_amount}}',
string(outputs('CalculateTotalAmount'))),
'{{consumption_variance}}',
string(outputs('CalculateConsumptionVariance'))),
'{{cost_variance}}',
string(outputs('CalculateConsumptionVariance'))),
'{{historical_avg_cost}}',
string(mul(items('ForEachMeter')['historical_avg_consumption_kwh'], items('ForEachMeter')['tariff_kwh']))),
'{{anomaly_type}}',
outputs('DetectAnomaly')),
'{{anomaly_percentage}}',
string(abs(outputs('CalculateConsumptionVariance'))))
```

### 10. Enviar Email con SendGrid

1. Agrega una acción **Send email (SendGrid)**
2. Crea nueva conexión con tu API Key de SendGrid
3. Configura los campos:

**To:** 
```
@items('ForEachMeter')['notification_email']
```

**From:**
```
facturas@epm.com.co
```

**From name:**
```
EPM - Facturas
```

**Subject:**
```
@concat('Factura de Consumo - Medidor ', items('ForEachMeter')['meter_code'], ' - ', formatDateTime(utcNow(), 'MMMM yyyy'))
```

**HTML Content:**
```
@outputs('ReplaceVariablesInTemplate')
```

**Reply To:**
```
soporte@epm.com.co
```

---

## 🔐 Configuración de Seguridad

### 1. Firewall de SQL Server

Para que Logic Apps acceda a tu SQL Server:

1. En Azure Portal → **SQL servers** → Tu servidor
2. **Firewall and virtual networks**
3. Agrega la regla:
   - **Rule name:** AllowAzureServices
   - **Start IP:** 0.0.0.0
   - **End IP:** 0.0.0.0

### 2. Almacenar Credenciales de Forma Segura

Usa **Azure Key Vault** en lugar de hardcodear credenciales:

1. Crea un **Key Vault**
2. Agrega tus secretos (API Keys, passwords)
3. En el Logic App, usa la conexión de Key Vault para obtener valores

---

## 🧪 Testing

### Test 1: Verificar Conexión a SQL
1. En el Logic App, ve a **Connections**
2. Verifica que todas las conexiones estén activas (verde)

### Test 2: Ejecutar Manualmente
1. Click en **Run** (en la parte superior)
2. Deberá procesar todos los medidores
3. Revisa que los correos lleguen

### Test 3: Revisar Logs
1. En **Overview** → **Run history**
2. Click en la ejecución más reciente
3. Expande cada acción para ver entradas y salidas

---

## 📊 Monitoreo y Alertas

### Agregar Alerta de Fallo

1. En el Logic App → **Alerts**
2. Crea una alerta:
   - **Condition:** Runs failed
   - **Threshold:** > 0
   - **Action:** Enviar email a administrador

### Application Insights

1. Agrega **Application Insights** al Logic App
2. Monitorea:
   - Duración promedio
   - Número de ejecuciones
   - Tasa de error

---

## 🚀 Deployment a Producción

### Checklist Final

- [ ] Todas las conexiones están probadas
- [ ] Las credenciales están en Key Vault (no hardcodeadas)
- [ ] El template HTML está en Blob Storage
- [ ] El trigger se ejecuta a la hora correcta
- [ ] Los emails se envían correctamente
- [ ] Se tiene configurada alerta de fallos
- [ ] Se puede ver el historial de ejecuciones

### Importar Flujo Completo

Si quieres importar directamente el flujo ya configurado:

1. Descarga `billing-email-workflow.json`
2. En Azure Portal → **Logic Apps** → **+Create**
3. Selecciona **Template deployment**
4. Carga el archivo JSON
5. Configura los parámetros de conexión
6. Click en **Create**

---

## 📞 Troubleshooting

| Problema | Solución |
|----------|----------|
| **Error al conectar SQL** | Verifica firewall de Azure, credenciales, y que SQL Server sea accesible |
| **Template HTML no encontrado** | Asegúrate de que el archivo está en `/email-templates/template.html` en Blob Storage |
| **Variables no se reemplazan** | Verifica que los nombres de variables coincidan exactamente (case-sensitive) |
| **Emails no se envían** | Verifica API Key de SendGrid, limite de rate, y que el conector esté autenticado |
| **Error de timeout** | Si hay muchos medidores, aumenta el timeout del Logic App o usa batches |

---

## 💡 Optimizaciones Futuras

1. **Batch emails:** Agrupar envíos para mejorar rendimiento
2. **Retry logic:** Reintentar envíos fallidos
3. **Webhook:** Recibir notificaciones de SendGrid sobre bounces
4. **Template dinámicos:** Diferentes templates por estrato socioeconómico
5. **Multiidioma:** Enviar facturas en español/inglés según preferencia
6. **Facturación PDF:** Agregar generación automática de PDF

