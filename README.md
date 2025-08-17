# Kantine Koning iOS App

Een native iOS-app voor het beheren van kantinediensten bij sportverenigingen. De app ondersteunt zowel teammanagers als verenigingsleden met verschillende rollen en rechten.

## Features

### 🔐 Accountloze Onboarding
- QR-code scanning voor clubregistratie
- Keuze tussen Teammanager en Verenigingslid
- Email verificatie voor teammanagers
- Team zoeken en selecteren voor verenigingsleden

### 📱 Multi-tenant Support
- Ondersteuning voor meerdere verenigingen per gebruiker
- Maximum 5 teams per gebruiker (cross-tenant)
- Verschillende rollen per vereniging mogelijk

### 🔔 Push Notificaties
- Gerichte notificaties voor geplande diensten
- Deep links naar specifieke teams
- Magic link enrollment voor veilige registratie

### 👥 Vrijwilligersbeheer
- Teammanagers: toevoegen/verwijderen van vrijwilligers
- Verenigingsleden: alleen-lezen toegang
- Realtime status updates (onbemand/gedeeltelijk/volledig)

## Code Structuur

```
Kantine Koning/
├── Kantine_KoningApp.swift          # App entry point
├── AppModel.swift                   # Core data model & business logic
├── BackendClient.swift              # API client (stubbed)
├── SecureStorage.swift              # Device credential storage
├── DesignSystem.swift               # UI theming & components
├── KeyboardHelpers.swift            # Keyboard management utilities
├── TeamHelpers.swift                # Team data conversion helpers
├── AppRouterView.swift              # Main app navigation
├── OnboardingFlowView.swift         # QR scan & enrollment flow
├── HomeView.swift                   # Home screen & dienst management
├── QRScannerView.swift              # Camera integration
└── Assets.xcassets/                 # Images, icons & branding
```

## Ondersteunde Flows

### Teammanager Flow
1. Scan QR-code van vereniging
2. Kies rol: "Teammanager"
3. Voer email adres in voor verificatie
4. Selecteer geautoriseerde teams
5. Bevestig enrollment via magic link
6. Ontvang push notificaties voor diensten
7. Beheer vrijwilligers voor diensten

### Verenigingslid Flow
1. Scan QR-code van vereniging
2. Kies rol: "Verenigingslid"
3. Zoek en selecteer teams (autocomplete)
4. Direct registratie (geen email vereist)
5. Ontvang push notificaties voor diensten
6. Alleen-lezen toegang tot dienstoverzicht

### Home Navigation
```
Home → Verenigingen → Teams → Diensten
  ↓        ↓         ↓         ↓
 🏠      Swipe     Swipe    Vrijwilliger
       Delete    Delete      beheer
```

## Tech Stack

- **SwiftUI** - Native iOS UI framework
- **MVVM** - Model-View-ViewModel architecture
- **AVFoundation** - Camera/QR scanning
- **Push Notifications** - APNs integration
- **Keychain** - Secure credential storage
- **Combine** - Reactive data binding

## Design System

- **Kleuren**: Wit met oranje accenten (`#ef8b3b`)
- **Fonts**: Comfortaa (headers), System (body)
- **Branding**: Kantine Koning logo met zig-zag onderstreping
- **Stijl**: Minimalistisch, consistent, toegankelijk

## Development

### Requirements
- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+

### Setup
1. Open `Kantine Koning.xcodeproj` in Xcode
2. Selecteer target device/simulator
3. Build & Run

### Backend Integration
De app gebruikt momenteel stubbed API calls in `BackendClient.swift`. Voor productie:
- Vervang stubs door echte `kantinekoning.com` endpoints
- Configureer push notification certificates
- Update enrollment token validatie

## Permissions

- **Camera**: Voor QR-code scanning
- **Notifications**: Voor dienst updates

---

Made with ❤️ for Dutch sports clubs
