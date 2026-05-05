# Arquitectura Completa: EPM Email + Logic Apps + SendGrid

## 🏗️ Diagrama de Flujo

```
┌─────────────────────────────────────────────────────────────────────┐
│                    AZURE LOGIC APPS (Orquestación)                  │
└─────────────────────────────────────────────────────────────────────┘
                                ↓
         ┌────────────────────────────────────────────┐
         │  Trigger: Recurrencia Mensual (5 de mes)   │
         └────────────────────────────────────────────┘
                                ↓
    ┌────────────────────────────────────────────────────────┐
    │      Paso 1: Conectar a SQL Server                     │
    │      Query: Obtener medidores + datos de facturación   │
    │      Fuente: vw_meters_context                         │
    └────────────────────────────────────────────────────────┘
                                ↓
    ┌────────────────────────────────────────────────────────┐
    │      Paso 2: Loop ForEach (para cada medidor)          │
    │      Procesa: 100+ medidores secuencialmente           │
    └────────────────────────────────────────────────────────┘
                                ↓
    ┌────────────────────────────────────────────────────────┐
    │   Paso 3: Obtener Template HTML de Blob Storage        │
    │   Ruta: /email-templates/template.html                │
    │   Storage: Azure Blob Storage                          │
    └────────────────────────────────────────────────────────┘
                                ↓
    ┌────────────────────────────────────────────────────────┐
    │     Paso 4: Calcular Valores (Compose Actions)         │
    │     • Consumo (lectura actual - anterior)              │
    │     • Costo energía (consumo × tarifa)                 │
    │     • Impuesto (energía × %)                           │
    │     • Total (energía + impuesto)                       │
    │     • Varianza consumo (% vs histórico)                │
    │     • Detectar anomalía (ALTO/BAJO/CERO)               │
    └────────────────────────────────────────────────────────┘
                                ↓
    ┌────────────────────────────────────────────────────────┐
    │  Paso 5: Reemplazar Variables en Template              │
    │  Reemplaza 28+ variables {{variable}}                  │
    │  Salida: HTML completamente personalizado              │
    └────────────────────────────────────────────────────────┘
                                ↓
    ┌────────────────────────────────────────────────────────┐
    │   Paso 6: Enviar Email a través de SendGrid            │
    │   • From: facturas@epm.com.co                          │
    │   • To: notification_email del cliente                 │
    │   • Subject: Factura - Medidor XXX - Mes              │
    │   • Body: HTML personalizado                           │
    │   • Reply-To: soporte@epm.com.co                       │
    └────────────────────────────────────────────────────────┘
                                ↓
                        ✅ Email Enviado
                    (o ❌ Log de Error)
```

---

## 📁 Estructura de Archivos

```
EstudIAEPM/
├── html/
│   ├── template.html                    ← Template HTML (incrustado)
│   ├── README.md                        ← Documentación del template
│   ├── LOGIC_APPS_INTEGRATION.md        ← Guía de integración
│   ├── ejemplo-datos.json               ← Datos de prueba
│   └── BillingEmailService.cs           ← (No usado - es para C#)
│
├── logic-apps/
│   ├── logic.json                       ← Tu flujo actual
│   ├── billing-email-workflow.json      ← Flujo completo para SendGrid
│   └── SETUP_GUIDE.md                   ← Guía paso a paso de configuración
│
├── sql/
│   ├── vw_meters_context.sql            ← Vista que obtiene datos
│   └── ...otros scripts
│
└── csv/
    └── ...datos de prueba
```

---

## 🔌 Conexiones Necesarias en Logic Apps

### 1. **SQL Server Connection**
```
Server:    epmserver.database.windows.net
Database:  EPM
Auth:      SQL Server Authentication
Query:     Obtiene todos los medidores activos
```

### 2. **Azure Blob Storage Connection**
```
Storage Account: tustorage.blob.core.windows.net
Container:       email-templates
File:            template.html
Access:          Read blob content
```

### 3. **SendGrid Connection**
```
API Key:   SG.xxxxxxxxxxxxxxxxxxxxx
Endpoint:  api.sendgrid.com
Action:    Send email (HTML)
```

---

## 📊 Flujo de Datos

```
SQL Database (vw_meters_context)
    │
    ├─ meter_code
    ├─ address
    ├─ notification_email
    ├─ socioeconomic_stratum
    ├─ tariff_kwh
    ├─ previous_reading
    ├─ current_reading
    ├─ historical_avg_consumption_kwh
    └─ tax_pct
    
         ↓ (Cálculos en Logic App)
    
    ├─ consumption_kwh = current - previous
    ├─ energy_cost = consumption × tariff
    ├─ tax_amount = energy_cost × (tax_pct / 100)
    ├─ total_amount = energy_cost + tax_amount
    ├─ consumption_variance = ((current - historical) / historical) × 100
    └─ anomaly_type = ALTO/BAJO/CERO/NORMAL
    
         ↓ (Reemplaza en template)
    
Template HTML (placeholder → datos reales)
    {{meter_code}}                    →  1002345678
    {{address}}                       →  Calle 50 #25-30
    {{consumption_kwh}}               →  360.25 kWh
    {{energy_cost}}                   →  $ 450,312.50
    {{total_amount}}                  →  $ 486,336.50
    ... (28+ variables más)
    
         ↓ (HTML personalizado)
    
SendGrid API
    │
    └─→ Email Service
        │
        └─→ 📧 Cliente recibe factura
```

---

## ⏱️ Tiempos de Ejecución

| Acción | Tiempo Estimado |
|--------|-----------------|
| Query SQL (100 medidores) | 2-5 segundos |
| Por cada medidor (cálculos + reemplazo) | 1-2 segundos |
| Envío SendGrid (por email) | 1-3 segundos |
| **Total para 100 medidores** | **3-7 minutos** |

### Optimizaciones posibles:
- Usar **parallel processing** en Logic Apps
- Implementar **batch sending** en SendGrid (máx 1000 emails/request)
- Usar **Azure Durable Functions** para mejor control

---

## 💰 Costos Estimados (Mes)

| Servicio | Uso | Costo |
|----------|-----|-------|
| **Logic Apps** | ~30 runs × ~500 acciones c/u = 15K acciones | ~$5 |
| **SQL Server** | Query executions (negligible) | ~$0 |
| **Azure Storage** | 1 archivo de 50KB | ~$0.01 |
| **SendGrid** | ~3,000 emails/mes (free tier) | $0 |
| **Total aproximado** | | **~$5/mes** |

*Para 100,000+ emails/mes: SendGrid pasa a plan pago ~$10-30/mes*

---

## 🔒 Seguridad

### ✅ Lo que está implementado:
- API Keys en SendGrid (no hardcodeadas)
- Credenciales SQL en conexión encriptada de Logic Apps
- Email de soporte público (no usuario/pass)
- HTTPS para todas las conexiones

### ⚠️ Recomendaciones adicionales:
1. Usa **Azure Key Vault** para almacenar API Keys
2. Activa **Managed Identity** en Logic Apps
3. Limita acceso a Blob Storage con **SAS tokens**
4. Audita logs con **Application Insights**
5. Encripta datos en SQL Server

---

## 🎯 Checklist de Implementación

### Fase 1: Preparación (30 min)
- [ ] Subir `template.html` a Blob Storage
- [ ] Verificar credenciales SQL
- [ ] Obtener API Key de SendGrid
- [ ] Preparar credenciales Azure

### Fase 2: Configuración (1-2 horas)
- [ ] Crear Logic App
- [ ] Configurar conexión SQL
- [ ] Agregar trigger de recurrencia
- [ ] Crear query de obtención de datos
- [ ] Agregar loop ForEach

### Fase 3: Lógica de Cálculo (30 min)
- [ ] Crear 6 acciones Compose para cálculos
- [ ] Validar expresiones
- [ ] Probar con datos de ejemplo

### Fase 4: Integración SendGrid (30 min)
- [ ] Configurar conexión SendGrid
- [ ] Crear acción Send email
- [ ] Reemplazar variables en template
- [ ] Validar HTML renderizado

### Fase 5: Testing (1 hora)
- [ ] Ejecutar manualmente con 1 medidor
- [ ] Verificar email recibido
- [ ] Ejecutar con 10 medidores
- [ ] Revisar logs y errores
- [ ] Hacer ajustes

### Fase 6: Producción (30 min)
- [ ] Configurar recurrencia mensual
- [ ] Agregar alertas
- [ ] Activar Application Insights
- [ ] Documentar proceso

**Tiempo total: ~4-5 horas**

---

## 🚀 Próximos Pasos

1. **Sube el template HTML a Blob Storage**
   ```powershell
   # Desde PowerShell
   az storage blob upload \
     --account-name tustorage \
     --container-name email-templates \
     --name template.html \
     --file C:\path\to\template.html
   ```

2. **Crea el Logic App en Azure Portal** (seguir SETUP_GUIDE.md)

3. **Prueba con un medidor** antes de producción

4. **Configura alertas** para monitorear ejecuciones

5. **Documenta el flujo** en tu wiki corporativo

---

## 📞 Soporte

Para problemas:
1. Revisa `SETUP_GUIDE.md` - Troubleshooting
2. Revisa `LOGIC_APPS_INTEGRATION.md` - Opciones alternativas
3. Consulta logs en Logic App → Run history

---

**Creado:** 2026-05-05
**Última actualización:** 2026-05-05
**Estado:** Listo para implementar ✅
