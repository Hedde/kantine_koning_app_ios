# Kantine Koning iOS App

Een native SwiftUI-app voor het beheren van kantinediensten bij sportverenigingen. Ondersteunt zowel teammanagers als verenigingsleden met gescheiden rechten, multi-tenant gebruik en push notificaties.

## ⚠️ Important: Device Identifiers & Testing

### identifierForVendor Behavior

De app gebruikt `UIDevice.current.identifierForVendor` als hardware identifier voor multi-enrollment support en reconciliation.

**Stabiel in productie (App Store):**
- ✅ App updates (1.0 → 2.0 → 3.0)
- ✅ Normaal gebruikersgedrag
- ✅ iOS updates
- ✅ Delete/reinstall (als er andere apps van dezelfde vendor op device staan)

**Verandert tijdens development/testing:**
- ❌ **TestFlight ↔ App Store switches** (verschillende signing)
- ❌ **Verschillende TestFlight builds** (afhankelijk van build settings)
- ❌ **Delete/reinstall als het de enige app van de vendor is**
- ❌ Device restore/reset

**Impact op reconciliation:**
Wanneer `identifierForVendor` verandert, ziet de backend dit als een nieuw device. De enrollments van het oude device worden binnen 1 uur weggereconciled (revoked) wanneer de app met de nieuwe identifier naar foreground komt. Dit is **verwacht gedrag** tijdens testing maar **heeft geen impact op productie gebruikers** die alleen App Store updates ontvangen.

**Testing aanbeveling:**
Wees bewust dat switchen tussen TestFlight en App Store builds de device identifier kan veranderen en enrollment cleanup triggert. Om betrouwbaar te testen, blijf bij één distributie methode per test sessie.

## Features

### 🔐 Accountloze onboarding
- QR-code scannen voor clubregistratie
- Rolkeuze: Teammanager of Verenigingslid
- Manager: e‑mail verificatie en teamselectie, bevestigen via magic link
- Lid: teams zoeken en direct aanmelden (geen e‑mail vereist)

### 📱 Multi-tenant
- Meerdere verenigingen en teams per gebruiker
- Limiet van maximaal 5 teams totaal (cross-tenant)
- Rollen per vereniging (manager/lid)

### 🔔 Push notificaties
- APNs-registratie en token doorgeven aan backend
- Notificaties verversen automatisch de lijst met diensten

### 🔄 Enrollment Reconciliation
- **Automatische sync** bij app foreground: App stuurt huidige enrollment state naar backend
- **Cleanup orphaned enrollments**: Backend revoked enrollments die niet meer in app bestaan
- **Safeguards**: 
  - Reconciliation alleen na tenant info refresh (voorkomt incomplete data)
  - Team code mapping MOET slagen (abort bij failures)
  - Throttling van 1 uur tussen syncs
- **Use case**: Herstelt inconsistenties door gefaalde deletion API calls of "Alles resetten"

### 👥 Vrijwilligersbeheer
- Managers: vrijwilligers toevoegen/verwijderen per dienst
- Leden: alleen-lezen toegang tot dienstinformatie

### 🧭 Navigatie
```
Home → Verenigingen → Teams → Diensten
  ↓        ↓         ↓         ↓
 🏠      Swipe     Swipe    Vrijwilliger
       Delete    Delete      beheer
```

**Auto-reset naar onboarding:**
- Wanneer het laatste team/vereniging wordt verwijderd via swipe-to-delete
- Wanneer "Alles resetten" wordt gebruikt in instellingen
- App keert automatisch terug naar QR-scan scherm

## Architectuur
- `AppStore` (ObservableObject) beheert appfasen: launching, onboarding, enrollmentPending, registered
- `DomainModel` met `Tenant`, `Team`, rollen (`manager`/`member`), persist via `UserDefaults` (`kk_domain_model`)
- Repositories: `EnrollmentRepository` en `DienstRepository` → `BackendClient` voor HTTP-calls
- **Data-Driven Architecture**: `AppStore.upcoming` als single source of truth voor diensten
- **Logging System**: `Logger` met debug/release flags voor productie-klare logging
- `BackendClient` base URL:
  - Debug: `http://localhost:4000`
  - Release: `https://kantinekoning.com`
  - Override via Info.plist key `API_BASE_URL`
- Push: `UNUserNotificationCenter` + `updateAPNsToken`, refresh bij ontvangst

## Deep links
- Device enroll (magic link): `kantinekoning://device-enroll?token=...` of web-variant op `...kantinekoning.com/.../device-enroll?token=...`
- CTA: `kantinekoning://cta/shift-volunteer?token=...` (placeholder-UI; wist pending CTA)

## QR-payloads
- `kantinekoning://tenant?slug=<tenant_slug>&name=<club_naam>`
- `kantinekoning://invite?tenant=<tenant_slug>&tenant_name=<club_naam>`
- Genest via `data=` parameter met daarin een van bovenstaande URLs

## Flows
### Teammanager
1. Scan QR-code → kies “Teammanager”
2. Voer e‑mail in → `fetchAllowedTeams`
3. Kies teams → `requestEnrollment`
4. Bevestig via magic link → `registerDevice` → appfase `registered`
5. Ontvang pushmeldingen, beheer vrijwilligers

### Verenigingslid
1. Scan QR-code → kies “Verenigingslid”
2. Zoeken/seleceren van teams (`searchTeams`)
3. Direct registreren → `registerMemberDevice`
4. Appfase `registered`, alleen-lezen diensten

## Multi-Tenant Architectuur ⚠️ BELANGRIJK

### 📊 Enrollment Model
- **Eén enrollment = Eén tenant + Specifieke teams + Eigen JWT token**
- **Meerdere enrollments mogelijk** voor hetzelfde device:
  - VV Wilhelmus - Manager voor JO11-3, JO11-5
  - VV Wilhelmus - Lid voor JO13-1 (aparte enrollment!)  
  - AGOVV - Lid voor JO10-5
- **Hardware identifier** linkt alle enrollments van hetzelfde fysieke device

### 🔑 Auth Token Strategy
- **Per tenant = Per JWT**: Elke tenant heeft eigen `signedDeviceToken`
- **Team filtering**: JWT bevat `team_codes` voor die specifieke enrollment
- **API calls**: ALTIJD per enrollment/tenant met juiste auth token

### 📡 API Call Patterns
```swift
// ✅ CORRECT: Per-tenant calls met eigen auth
for tenant in model.tenants.values {
    let tenantBackend = BackendClient()
    tenantBackend.authToken = tenant.signedDeviceToken  // Tenant-specific JWT
    tenantBackend.fetchDiensten(tenant: tenant.slug)
}

// ❌ FOUT: Single call met één JWT (mist andere tenants)  
// NOTE: Deze approach is deprecated - gebruik enrollment-specific tokens
let backend = BackendClient()
backend.authToken = model.primaryAuthToken  // Alleen eerste tenant
backend.fetchAllDiensten()  // Mist enrollments van andere tenants
```

### 🏗️ Backend Enrollment Storage
- **Tabel**: `device_enrollments` (public schema)
- **Per enrollment**: `device_id` (unique per tenant), `tenant_slug`, `team_codes[]`, `role`
- **Hardware linking**: `hardware_identifier` (UUID from `identifierForVendor`, consistent across enrollments)
- **Multi-tenant lookup**: `WHERE hardware_identifier = X AND status = active`
- **Note**: Hardware identifier is the vendor UUID only, not concatenated with bundle ID

## Diensten en vrijwilligers
- **Ophalen**: Per tenant via `/api/mobile/v1/diensten?tenant=slug` met tenant-specifieke JWT
- **Tijdvenster**: Standaard 365 dagen (1 jaar) in het verleden voor volledige seizoensgeschiedenis, 60 dagen in de toekomst (configureerbaar via `past_days`/`future_days`)
- **Filtering**: Backend filtert op `team_codes` uit JWT token van die enrollment
- **Aggregatie**: Client-side dedup en sortering (toekomst eerst)
- **Validaties**: Managers kunnen vrijwilligers toevoegen/verwijderen; naam ≤ 15 tekens, geen duplicaten

## Leaderboard
- **Tenant-specifiek**: `/api/mobile/v1/leaderboard?tenant=slug&team_id=X` (highlight eigen team)
- **Globaal**: `/api/mobile/v1/leaderboard/global?tenant=slug&team_id=X` (cross-tenant)
- **Performance**: Top 10 + eigen team (als buiten top 10)
- **Opt-out**: Tenants kunnen zich afmelden voor globale leaderboard

## Backend integratie
- **Endpoints**: `/api/mobile/v1/enrollments/*`, `/device/*`, `/diensten`, `/teams/search`, `/leaderboard/*`, vrijwilligers-CRUD
- **Auth**: Signed device token uit `registerDevice` als Bearer token **PER TENANT**
- **APNs**: `updateAPNsToken` verstuurt ook build-omgeving en appversie
- **Reconciliation**: `POST /enrollments/sync` - App stuurt enrollment state, backend cleanup orphans
  - Request: `{"enrollments": [{"tenant_slug", "role", "team_codes", "hardware_identifier"}]}`
  - Response: `{"synced": true, "cleanup_summary": {"enrollments_revoked", "teams_removed"}}`
  - Guards: Alleen binnen hardware_identifier scope, respect voor `enrollment_open` en `season_ended`

## Requirements
- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+

## Setup
1. Open `Kantine Koning.xcodeproj` in Xcode
2. Selecteer target device/simulator
3. Build & Run

Optioneel: override backend via Info.plist → `API_BASE_URL`.

## Permissions
- Camera: QR-code scanning
- Notifications: dienstupdates en CTA’s

## ⚠️ Multi-Tenant Development Pitfalls

### 🚨 Auth Token Mistakes (VAAK VOORKOMEND)
```swift
// ❌ FOUT: Gebruik van primaryAuthToken voor alle API calls (DEPRECATED)
let token = store.model.primaryAuthToken  // Alleen eerste tenant!
let backend = BackendClient()
backend.authToken = token
backend.fetchDiensten(tenant: "agovv")  // Fails - token is voor vvwilhelmus

// ✅ CORRECT: Gebruik enrollment-specific tokens
let backend = BackendClient()
backend.authToken = store.model.tenants["agovv"]?.signedDeviceToken
backend.fetchDiensten(tenant: "agovv")  // Success - juiste token voor agovv

// ✅ CORRECT: Tenant-specifieke tokens
let tenant = store.model.tenants["agovv"]
backend.authToken = tenant.signedDeviceToken  // AGOVV-specifieke JWT
backend.fetchDiensten(tenant: "agovv")  // Works - juiste teams in JWT
```

### 🏗️ Enrollment Complexity
- **1 Device** kan **meerdere enrollments** hebben voor **dezelfde tenant**:
  - Manager enrollment: JO11-3, JO11-5 (full access)
  - Lid enrollment: JO13-1 (read-only)
- **Hardware identifier** is de **enige** consistente link tussen enrollments
- **Device ID** is **uniek per enrollment** (niet per device!)

### 📡 API Design Principes
1. **ALTIJD per-enrollment calls** doen met enrollment-specifieke JWT
2. **NOOIT aggregated endpoints** gebruiken die cross-tenant data verwachten
3. **Client-side aggregatie** van multiple enrollment responses
4. **Deduplicatie** op dienst ID (zelfde dienst kan in multiple responses zitten)

### 🔍 Debugging Multi-Tenant Issues
```elixir
# Backend: Check enrollments voor device
[DEVICES] Found hardware_identifier=iPhone_ABC123
[DEVICES] Found 3 enrollments: vvwilhelmus(manager), vvwilhelmus(lid), agovv(lid)

# iOS: Check tenant tokens
print("Tenant \(tenant.slug): token=\(tenant.signedDeviceToken?.prefix(20))")
```

## 🗄️ Data-Driven Architectuur

### Single Source of Truth
De app gebruikt een vereenvoudigde data-driven benadering voor optimale consistentie:

- **Centraal data model**: `AppStore.upcoming` bevat alle diensten data
- **Automatische UI updates**: SwiftUI's `@Published` zorgt voor reactive updates
- **Direct API updates**: Volunteer operaties → API call → refresh data model → UI update
- **Push notification sync**: Ontvangen push → `refreshDiensten()` → bijgewerkte UI

### Data Flow
```swift
// Volunteer toevoegen/verwijderen
store.addVolunteer(tenant: tenant, dienstId: id, name: name) { result in
    // API success → refreshDiensten() → fresh data → UI update
}

// UI components gebruiken dynamic lookups
private var dienst: Dienst? {
    store.upcoming.first { $0.id == dienstId }  // Altijd actuele data
}
```

### Voordelen van Data-Driven Approach
- **Geen cache invalidation**: Single source of truth elimineert synchronisatie problemen
- **Automatische consistency**: Wijzigingen propageren direct naar alle UI componenten
- **Eenvoudige debugging**: Duidelijke data flow zonder cache complexity
- **Performance**: Data blijft in geheugen na eerste load (gratis caching)

### CachedAsyncImage
Eenvoudige AsyncImage replacement met in-memory caching:
```swift
CachedAsyncImage(url: logoURL) { image in
    image.resizable().scaledToFit()
} placeholder: {
    Image(systemName: "building.2.fill")
}
```

## 📋 Logging Systeem

### Production-Ready Logging
Centraal logging systeem met debug/release onderscheid:

```swift
// Debug builds: Alle logs zichtbaar
Logger.volunteer("Adding volunteer to dienst")
Logger.network("API call completed") 
Logger.error("Critical failure") // Altijd gelogd

// Production builds: Alleen errors via os_log
```

### Log Categorieën
- `Logger.debug()` - Alleen debug builds
- `Logger.info()` - Beide builds
- `Logger.warning()` - Beide builds  
- `Logger.error()` - Altijd gelogd
- `Logger.success()` - Alleen debug builds
- Domain-specific: `volunteer()`, `network()`, `auth()`, `email()`, `push()`, `leaderboard()`, `qr()`, `enrollment()`

### Build Configuratie
```swift
#if DEBUG
    // Debug builds: Alle logs via print() naar Xcode console
    return true
#elseif ENABLE_LOGGING
    // Release builds met ENABLE_LOGGING flag: Volledige logging
    return true
#else
    // Production builds: Alleen errors + runtime toggle
    return loggingConfig.isLoggingEnabled
#endif
```

## 🏗️ Build Schemes & Configuratie

### Scheme Configuratie Overzicht

| **Scheme** | **Build Config** | **Logging** | **APNS Environment** | **Build Environment** | **Gebruik** |
|------------|------------------|-------------|---------------------|---------------------|-------------|
| **Release Testing** | Debug | ✅ **AAN** (`ENABLE_LOGGING=YES`, `DEBUG` flag) | **Sandbox** | `"development"` | Development & testing met volledige logs |
| **Release** | Release | ❌ **UIT** (`ENABLE_LOGGING=NO`, geen flags) | **Production** | `"production"` | Production deployment |

### 🚨 KRITIEK: Scheme vs Build Environment Mapping

**iOS App Entitlements:**
- **Release Testing** scheme → `Debug` build → `aps-environment: development` → Server detecteert **sandbox**
- **Release** scheme → `Release` build → `aps-environment: production` → Server detecteert **production**

**Backend Auto-Detection Logic:**
```elixir
case device.build_environment do
  env when env in ["development", "debug"] -> "sandbox"   # APNs Sandbox
  _ -> "production"                                       # APNs Production
end
```

### Build Environment Detection

```swift
private func getBuildEnvironment() -> String {
    #if DEBUG
    return "development"                 // Release Testing scheme → Sandbox APNS
    #elseif ENABLE_LOGGING
    return "testing"                     // Niet gebruikt
    #else
    return "production"                  // Release scheme → Production APNS
    #endif
}
```

### 🔍 APNS Environment Troubleshooting

**Environment Mismatch Detectie:**
```swift
// Check in device enrollment API response
let buildEnv = device.buildEnvironment
let apnsEnv = buildEnv == "development" ? "sandbox" : "production"
Logger.push("Device build: \(buildEnv) → APNS: \(apnsEnv)")
```

**Server-side Verification:**
```elixir
# Check in IEx console
device = Repo.get_by(DeviceEnrollment, team_manager_email: "user@example.com")
detected_env = case device.build_environment do
  env when env in ["development", "debug"] -> "sandbox"
  _ -> "production"
end
IO.puts("Device build: #{device.build_environment} → APNS: #{detected_env}")
```

### APNS Token Logging

Met de uitgebreide APNS logging zie je nu bij elke token update:

```
🔄 APNS Token Update Request
  → Token: abcd1234567890...
  → Build Environment: development
  → Detected APNS Environment: sandbox
  → Is New Token: true
  → Time Since Last Update: 3600.0s
  → Has Auth: true
  → Using auth token: xyz987654321...
✅ APNS token update SUCCESS (took 0.45s)
  → Final Environment: sandbox
  → Token cached for future comparisons
```

### Scheme Usage Guidelines

**Voor Development & Testing:**
- Gebruik **Release Testing** scheme voor dagelijkse development en testing
- Volledige logging en debug informatie
- Test tegen APNs Sandbox environment
- `build_environment: "development"` wordt naar server gestuurd
- Optimized build maar met alle debugging mogelijkheden

**Voor Production:**
- Gebruik **Release** scheme voor App Store builds  
- Geen logging overhead voor performance
- Production APNs environment
- `build_environment: "production"` wordt naar server gestuurd

### Backend Environment Mapping

De app detecteert automatisch de juiste backend environment:

```swift
let buildEnvironment: String = {
    #if DEBUG
    return "development"  // → APNs Sandbox (Release Testing scheme)
    #elseif ENABLE_LOGGING  
    return "development"  // → Niet gebruikt
    #else
    return "production"   // → APNs Production (Release scheme)
    #endif
}()
```

**Server Environment Detection:**
```elixir
def determine_apns_environment(device_enrollment) do
  case System.get_env("APNS_FORCE_ENV") do
    env when env in ["sandbox", "production"] -> env
    _ ->
      if device_enrollment.is_test_user do
        "sandbox"
      else
        case device_enrollment.build_environment do
          env when env in ["development", "debug"] -> "sandbox"
          _ -> "production"  # production, release, appstore, or nil
        end
      end
  end
end
```

Dit zorgt ervoor dat:
- **Release Testing** → `build_environment: "development"` → APNs Sandbox
- **Release** → `build_environment: "production"` → APNs Production

### 🚨 Common Configuration Mistakes

**❌ Environment Mismatch:**
- App gebouwd met **Release** scheme (production entitlements)
- Server heeft `APNS_ENV=sandbox` environment variable
- **Resultaat**: APNS timeouts - sandbox credentials proberen production tokens

**✅ Correct Configuration:**
- App: **Release** scheme → `build_environment: "production"`
- Server: **Geen** `APNS_ENV` environment variable (auto-detection)
- **Resultaat**: Server gebruikt production APNS voor production device

**🔧 Quick Fix Commands:**
```bash
# Remove environment override (AANBEVOLEN)
fly secrets unset APNS_ENV -a kantine-koning

# Or set explicit environment
fly secrets set APNS_ENV=production -a kantine-koning
```

### 🔧 Logging Configuratie Opties

**1. Release Testing Scheme**
- Alle logging altijd enabled
- Volledige console output 
- Structured debug logging
- APNs Sandbox environment

**2. Release Scheme**
- Logging uitgeschakeld voor performance
- Alleen critical errors gelogd
- APNs Production environment

**3. Build Info Check**
```swift
Logger.buildInfo  // "Release Testing Build" / "Production Build"
Logger.isLoggingEnabled  // true/false
```

### Structured Debug Logging
Voor development debugging met visuele scheiding:

```swift
// Section separators voor grote operaties
Logger.section("APP BOOTSTRAP")
Logger.bootstrap("Initializing AppStore")

// HTTP request/response logging met timing
Logger.httpRequest(method: "GET", url: url, headers: headers)
Logger.httpResponse(statusCode: 200, url: url, responseTime: 0.5)

// User interaction tracking
Logger.userInteraction("Tap", target: "Settings Button", context: ["state": "open"])

// Performance monitoring
Logger.performanceMeasure("Refresh Diensten", duration: 1.2, additionalInfo: "50 items")

// View lifecycle
Logger.viewLifecycle("HomeHostView", event: "onAppear", details: "tenants: 3")
```

### Global Error Handling
iOS best practices voor exception handling:

```swift
// Automatische error categorisatie
error.handle(context: "Network request", showToUser: true)

// Custom app errors
throw AppError.networkUnavailable
throw AppError.validationFailed("Invalid email")

// Global uncaught exception handler
// Logs crashes in debug, reports to service in production
```

## Troubleshooting / Bekende beperkingen

### 📱 Push Notification Issues

**Push notifications niet ontvangen:**

1. **Check Build Scheme:**
   ```swift
   // In app logs
   Logger.push("Build environment: \(getBuildEnvironment())")
   // Should be "development" for testing, "production" for App Store
   ```

2. **Verify Entitlements:**
   - **Release Testing** scheme → `aps-environment: development` 
   - **Release** scheme → `aps-environment: production`

3. **Check Server Environment:**
   ```bash
   # Check backend APNS configuration
   fly ssh console -a kantine-koning
   # In IEx:
   IO.puts("APNS_ENV: #{System.get_env("APNS_ENV")}")
   # Should be nil (auto-detection) or match app environment
   ```

4. **Environment Mismatch Fix:**
   ```bash
   # Remove server environment override (RECOMMENDED)
   fly secrets unset APNS_ENV -a kantine-koning
   
   # This enables auto-detection based on device.build_environment
   ```

5. **Test Push Manually:**
   ```elixir
   # In production IEx console
   alias KantineKoning.{Devices.DeviceEnrollment, Repo}
   device = Repo.get_by(DeviceEnrollment, team_manager_email: "your@email.com")
   KantineKoning.Notifications.APNS.send_alert_to_device(device, "Test", "Manual test")
   ```

### 🔧 Build Configuration Issues

**Wrong APNS environment detected:**
- **Problem**: App built with Release scheme but server uses sandbox
- **Solution**: Ensure no `APNS_ENV` environment variable on server (use auto-detection)
- **Verify**: Device enrollment should have `build_environment: "production"` for Release builds

**Logging not working in Release builds:**
- **Expected**: Release scheme has logging disabled for performance
- **Debug**: Use Release Testing scheme for development with full logging

### 🌐 Multi-Tenant Issues

- Max 5 teams per gebruiker (enforced bij enrollment en member-registratie)
- Vrijwilliger toevoegen kan alleen voor toekomstige diensten en enkel als manager
- **Auto-reset gedrag**: Bij verwijderen van laatste team/vereniging keert de app automatisch terug naar onboarding
- "Alles resetten" wist lokaal en probeert backend-opschoning indien auth-token aanwezig
- **Multi-tenant**: Gebruik ALTIJD enrollment-specifieke JWT tokens via `model.authTokenForTeam()` of `tenant.signedDeviceToken`, NIET `primaryAuthToken`
- **Data synchronisatie**: Bij netwerkproblemen kan `refreshDiensten()` handmatig aangeroepen worden om data bij te werken
- **Simulator rebuilds**: Token/enrollment data kan verloren gaan bij rebuild - re-enroll je teams indien nodig

### 🚨 Common Configuration Mistakes

| **Issue** | **Symptoms** | **Fix** |
|-----------|--------------|---------|
| Environment mismatch | Push timeouts, no notifications | `fly secrets unset APNS_ENV` |
| Wrong build scheme | Unexpected APNS environment | Use Release for production, Release Testing for development |
| Invalid device token | APNS 400 errors | Re-enroll device, check token format |
| Expired JWT | API 401 errors | Device re-enrollment needed |

## 🔐 Export Compliance

Voor App Store submission is encryption compliance geconfigureerd:

```xml
<!-- In project.pbxproj build settings -->
ITSAppUsesNonExemptEncryption = NO;
```

**Betekenis:**
- ✅ **NO**: App gebruikt alleen standaard iOS encryptie (HTTPS, Keychain, etc.)
- ❌ **YES**: App implementeert custom encryption algoritmes

**Resultaat:** Geen export compliance vragen meer bij App Store Connect uploads.

---

Made with ❤️ for Dutch sports clubs
