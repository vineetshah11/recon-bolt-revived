# 📑 Project Overview & Architecture Reference

## Repositories
- **Main Working Repository**: `https://github.com/vineetshah11/recon-bolt-revived` (Private)
- **Original Source Code**: Based on DT's private Recon Bolt branch (655 Swift/SwiftUI files).
- **API Documentation references**: `https://github.com/vineetshah11/valorant-api-docs`

---

## What Has Already Been Completed
1. **Repository Setup**: Initialized and pushed to `vineetshah11/recon-bolt-revived`.
2. **Pro Paywall Completely Removed**:
   - In `Shared/Model/InAppStore.swift`, `ownsProVersion` and `owns()` have been overridden to unconditionally return `true`.
   - All premium features (widgets, pro stats, themes) are permanently unlocked for free.
3. **Instalock Kept Active**:
   - `AgentPickerView.swift` and `AgentSelectView.swift` retain their pre-game agent selection and lock-in API calls (`$0.lockInAgent(...)`).
4. **Cloudflare Auth Bypass Created**:
   - Created `Shared/Views/Settings/RiotWebAuthView.swift`.
   - Uses `WKWebView` to authenticate directly against `https://auth.riotgames.com/authorize` and extracts OAuth tokens from the redirect URL fragment.

---

## What Needs to Be Done (Priority Order)
1. **GitHub Actions CI (`.github/workflows/build-ipa.yml`)**:
   - Automate compiling the project on a GitHub macOS runner to produce `Recon Bolt.ipa` as a downloadable artifact.
2. **Wire `RiotWebAuthView`**:
   - Connect the web login view to `LoginForm.swift` and `AccountManager.swift`.
3. **API & Roster Audit**:
   - Ensure newer agents and API version strings are up-to-date.

---

## Tech Stack
- **Language**: Swift 5.7+
- **Framework**: SwiftUI (iOS 15.0+ deployment target)
- **Dependencies**: Swift Package Manager (`ValorantAPI`, `HandyOperators`, `SwiftUIMissingPieces`, `UserDefault`, `KeychainAccess`)
- **Build Tool**: Xcode 15 / 16 (`xcodebuild`)

