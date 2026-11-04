# CLAUDE.md — Recon Bolt Revival Guide for Claude Code

## Project Overview
This is **Recon Bolt Revived**, a revived, modern version of the discontinued open-source Valorant companion iOS app (originally by Julian Dunskus and DT).
- **Platform**: iOS (SwiftUI, iOS 15+)
- **Core Functionality**: View live match status, pre-game agent selection (instalock kept active per user requirement), skin shop, rank progression, career match history, and account stats.
- **Goal**: Make a 100% free, working version (similar to Valpaw.com but free and with instalock intact) and produce an installable `.ipa` via GitHub Actions CI for Sideloadly / AltStore sideloading on Windows/iOS without needing a paid Apple Developer account.

---

## Current Architecture & Status
- **Paywall Removal**: Completed in `Shared/Model/InAppStore.swift`. `ownsProVersion` and `owns()` now unconditionally return `true`.
- **Auth Fix (Cloudflare bypass)**: Created `Shared/Views/Settings/RiotWebAuthView.swift`.
  - Riot's old `auth.riotgames.com/api/v1/authorization` direct URLSession calls fail due to Cloudflare JA3/JA4 TLS fingerprinting and JS bot challenges.
  - `RiotWebAuthView.swift` uses `WKWebView` to load Riot's OAuth login page (`https://auth.riotgames.com/authorize`). The user enters credentials in the real WebKit browser engine, Cloudflare passes natively, and the view intercepts the redirect fragment `#access_token=...&id_token=...&expires_in=...`.

---

## Primary Tasks Assigned to Claude Code

### Task 1: GitHub Actions CI/CD `.ipa` Build Workflow (HIGHEST PRIORITY)
**Goal**: We need automated `.ipa` generation via GitHub Actions macOS runners (`macos-14`), so users on Windows don't need a Mac to build the app.
- Create `.github/workflows/build-ipa.yml`.
- Workflow triggers on `push` to `main` and `workflow_dispatch`.
- Steps:
  1. Check out repository with submodules (`submodules: recursive`).
  2. Select Xcode 15 or 16 (`xcrun` / `DEVELOPER_DIR`).
  3. Resolve Swift Package dependencies (`xcodebuild -resolvePackageDependencies`).
  4. Build and archive for iOS Device (e.g. `generic/platform=iOS`):
     - Disable strict code signing for CI (use `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`, `CODE_SIGN_IDENTITY=""`).
     - Produce `Recon Bolt.xcarchive`.
  5. Package into an unsigned / ad-hoc `.ipa` (`Payload/Recon Bolt.app` zipped into `Recon Bolt.ipa`).
  6. Upload `Recon Bolt.ipa` as a GitHub Actions workflow artifact with 90-day retention.

### Task 2: Wire `RiotWebAuthView` into App Sign-In Flow
**Goal**: Replace the deprecated username/password form with the new WKWebView sign-in.
- Inspect `Shared/Views/Settings/LoginForm.swift` and `Shared/Model/AccountManager.swift`.
- In `LoginForm.swift`:
  - Provide a prominent "Sign in with Riot Games" button that opens `RiotWebAuthView`.
  - When tokens (`WebAuthTokens`) are captured:
    - Pass them into `accountManager.addAccount(using: tokens)`.
- In `Shared/Model/AccountManager.swift`:
  - Add `addAccount(using tokens: WebAuthTokens)`:
    - Construct or initialize an `APISession` using the extracted `accessToken`, `idToken`, and fetch entitlements/userID/location.
    - Store the session into Keychain (`context.keychain`).
- Ensure graceful error presentation if the user cancels the web view.

### Task 3: API Endpoints & Valorant Assets Audit
**Goal**: Ensure endpoints match current Valorant specifications.
- Verify `https://valorant-api.com` endpoints for current agent UUIDs, maps, and weapons (check new agents: Iso, Clove, Vyse, Tejo).
- In `ValorantAPI`: Verify `clientVersion` fetcher handles current Riot release tags so headers don't cause 400 Bad Request.

---

## Git & Submission Guidelines
- Work directly in this repository.
- Run tests / verify Xcode project integrity if tooling is available.
- Commit clean, descriptive commit messages:
  - `feat(ci): add GitHub Actions IPA build workflow`
  - `feat(auth): integrate RiotWebAuthView into LoginForm and AccountManager`
- Push directly to `origin main` or create a branch and open a PR.
