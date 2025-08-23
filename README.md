# Kantine Koning iOS App

Een native SwiftUI-app voor het beheren van kantinediensten bij sportverenigingen. Ondersteunt zowel teammanagers als verenigingsleden met gescheiden rechten, multi-tenant gebruik en push notificaties.

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

## Architectuur
- `AppStore` (ObservableObject) beheert appfasen: launching, onboarding, enrollmentPending, registered
- `DomainModel` met `Tenant`, `Team`, rollen (`manager`/`member`), persist via `UserDefaults` (`kk_domain_model`)
- Repositories: `EnrollmentRepository` en `DienstRepository` → `BackendClient` voor HTTP-calls
- **Caching Layer**: `CacheManager` + `CachedRepositories` voor offline-first ervaring
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
- **Hardware linking**: `hardware_identifier` (consistent across enrollments)
- **Multi-tenant lookup**: `WHERE hardware_identifier = X AND status = active`

## Diensten en vrijwilligers
- **Ophalen**: Per tenant via `/api/mobile/v1/diensten?tenant=slug` met tenant-specifieke JWT
- **Tijdvenster**: Standaard 30 dagen in het verleden, 60 dagen in de toekomst (configureerbaar via `past_days`/`future_days`)
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

## 🗄️ Caching Systeem

### Offline-First Architectuur
De app gebruikt een intelligente caching laag voor optimale gebruikerservaring:

- **Directe weergave**: Cached data wordt onmiddellijk getoond
- **Achtergrond refresh**: Fresh data wordt parallel opgehaald
- **Graceful degradation**: Bij netwerkfouten blijft cached data beschikbaar

### CacheManager Features
```swift
// Data caching met TTL
CacheManager.shared.cache(response, forKey: "diensten_vvwilhelmus", ttl: 300)

// Image caching voor tenant logo's
CacheManager.shared.cacheImage(image, forURL: logoURL)

// Smart retrieval: fresh, stale, of miss
let result = CacheManager.shared.getCached(DienstDTO.self, forKey: key)
```

### Cache Configuratie
- **Data TTL**: 5 minuten (diensten), 1 uur (tenant info)
- **Image TTL**: 24 uur
- **Storage**: Memory + Disk (100MB limiet)
- **Cleanup**: Automatisch bij app start

### CachedAsyncImage
Drop-in replacement voor `AsyncImage` met caching:
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

| **Scheme** | **Build Config** | **Logging** | **APNS Environment** | **Gebruik** |
|------------|------------------|-------------|---------------------|-------------|
| **Release Testing** | Debug | ✅ **AAN** (`ENABLE_LOGGING=YES`, `DEBUG` flag) | **Sandbox** | Development & testing met volledige logs |
| **Release** | Release | ❌ **UIT** (`ENABLE_LOGGING=NO`, geen flags) | **Production** | Production deployment |

### Build Environment Detection

```swift
private func getBuildEnvironment() -> String {
    #if DEBUG
    return "development (sandbox)"        // Release Testing scheme
    #elseif ENABLE_LOGGING
    return "testing (sandbox)"           // Niet gebruikt
    #else
    return "production"                  // Release scheme
    #endif
}
```

### APNS Token Logging

Met de uitgebreide APNS logging zie je nu bij elke token update:

```
🔄 APNS Token Update Request
  → Token: abcd1234567890...
  → Build Environment: development (sandbox)
  → Is New Token: true
  → Time Since Last Update: 3600.0s
  → Has Auth: true
  → Using auth token: xyz987654321...
✅ APNS token update SUCCESS (took 0.45s)
  → Environment: development (sandbox)
  → Token cached for future comparisons
```

### Scheme Usage Guidelines

**Voor Development & Testing:**
- Gebruik **Release Testing** scheme voor dagelijkse development en testing
- Volledige logging en debug informatie
- Test tegen APNs Sandbox environment
- Optimized build maar met alle debugging mogelijkheden

**Voor Production:**
- Gebruik **Release** scheme voor App Store builds
- Geen logging overhead voor performance
- Production APNs environment

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

Dit zorgt ervoor dat:
- **Release Testing** → APNs Sandbox gebruikt
- **Release** → APNs Production gebruikt

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
- Max 5 teams per gebruiker (enforced bij enrollment en member-registratie)
- Vrijwilliger toevoegen kan alleen voor toekomstige diensten en enkel als manager
- "Alles resetten" wist lokaal en probeert backend-opschoning indien auth-token aanwezig
- **Multi-tenant**: Gebruik ALTIJD enrollment-specifieke JWT tokens via `model.authTokenForTeam()` of `tenant.signedDeviceToken`, NIET `primaryAuthToken`
- **Cache invalidatie**: Bij kritieke data-wijzigingen kan cache handmatig gewist worden via `CacheManager.shared.clearCache()`

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
