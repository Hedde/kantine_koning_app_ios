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

## Diensten en vrijwilligers
- Ophalen per tenant via `/api/mobile/v1/diensten`, client-side dedup en sortering (toekomst eerst)
- Managers kunnen vrijwilligers toevoegen/verwijderen via API; validaties: geen verleden, naam ≤ 15 tekens, geen duplicaten

## Backend integratie
- Endpoints: `/api/mobile/v1/enrollments/*`, `/device/*`, `/diensten`, `/teams/search`, vrijwilligers-CRUD
- Auth: signed device token uit `registerDevice` als Bearer token
- APNs: `updateAPNsToken` verstuurt ook build-omgeving en appversie

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

## Troubleshooting / Bekende beperkingen
- Max 5 teams per gebruiker (enforced bij enrollment en member-registratie)
- Vrijwilliger toevoegen kan alleen voor toekomstige diensten en enkel als manager
- “Alles resetten” wist lokaal en probeert backend-opschoning indien auth-token aanwezig

---

Made with ❤️ for Dutch sports clubs
