# 📋 Copy-Paste Prompts for Claude Code

When you launch `claude` in the repository root, you can paste any of the following tasks. Each prompt is self-contained and tells Claude Code exactly what to do.

---

### 🌟 Task 1: Create GitHub Actions Workflow for Building the `.ipa` (Highest Impact!)
> **Why this helps**: Vineet is on Windows and cannot run `xcodebuild` locally. Having GitHub Actions automatically build the `.ipa` on a free macOS runner means Vineet can download the `.ipa` straight from GitHub and sideload it using Sideloadly on Windows!

**Prompt to paste into Claude Code:**
```text
Please create a GitHub Actions workflow in `.github/workflows/build-ipa.yml` to build and export an unsigned / ad-hoc iOS `.ipa` for this project.

Requirements:
1. Trigger on `push` to `main`, `pull_request`, and `workflow_dispatch` (manual trigger).
2. Runs on `macos-14` (or latest macOS runner with Xcode 15/16).
3. Check out repository recursively to include git submodules.
4. Set up Xcode using default installed versions.
5. Resolve Swift package dependencies.
6. Build and archive using `xcodebuild`:
   - Scheme: "Recon Bolt"
   - Configuration: Release
   - SDK: iphoneos
   - Set CODE_SIGNING_ALLOWED=NO, CODE_SIGNING_REQUIRED=NO, CODE_SIGN_IDENTITY=""
7. Create an `.ipa` package from the resulting `.xcarchive/Products/Applications/Recon Bolt.app` by wrapping it into a `Payload` folder and zipping to `Recon Bolt.ipa`.
8. Upload `Recon Bolt.ipa` as a GitHub Actions artifact (name: `recon-bolt-ipa`, retention-days: 90).
9. Verify the YAML syntax and commit when ready.
```

---

### 🌟 Task 2: Wire `RiotWebAuthView` into Login Flow
> **Why this helps**: Riot's old programmatic auth gets 403 Cloudflare errors. We already wrote `Shared/Views/Settings/RiotWebAuthView.swift` which uses `WKWebView` to bypass Cloudflare. We now need this connected to the app's sign-in sheet.

**Prompt to paste into Claude Code:**
```text
Please inspect `Shared/Views/Settings/RiotWebAuthView.swift`, `Shared/Views/Settings/LoginForm.swift`, and `Shared/Model/AccountManager.swift`.

Currently, `LoginForm.swift` accepts raw username & password credentials, but Riot's direct auth API is blocked by Cloudflare JA3/TLS fingerprinting. We created `RiotWebAuthView.swift` to handle web-based OAuth authentication.

Please update the login flow:
1. In `LoginForm.swift`:
   - Add a prominent primary button: "Sign In with Riot Games" that opens `RiotWebAuthView` in a sheet.
   - When `RiotWebAuthView` completes with `WebAuthTokens`, pass the tokens to `accountManager.addAccount(using: tokens)`.
   - Keep a fallback option or collapse the old username/password fields so users aren't confused.
2. In `AccountManager.swift`:
   - Add `func addAccount(using tokens: WebAuthTokens) async throws`.
   - Wire the tokens to construct or update an `APISession`, populate `userID`, `location`, and `entitlementsToken`, and save the session to Keychain.
3. Verify that there are no syntax errors or missing symbol definitions in the Swift code.
```

---

### 🌟 Task 3: Check Current Valorant API Endpoints & New Agents
> **Why this helps**: Ensures the app doesn't crash or show blank icons when encountering newer Valorant agents (like Iso, Clove, Vyse, Tejo) or recent Riot API changes.

**Prompt to paste into Claude Code:**
```text
Please audit the Valorant API integration in the project and `ValorantAPI` package references:
1. Check how agent data, icons, and IDs are retrieved (whether dynamically via `https://valorant-api.com` or hardcoded enums).
2. Verify that newly added Valorant agents (Iso, Clove, Vyse, Tejo, etc.) are handled properly without crashes in `AgentPickerView.swift` and `AgentSelectView.swift`.
3. Check the client version fetcher in `ValorantAPI` (or game config requests) to make sure headers like `X-Riot-ClientVersion` don't send deprecated format strings that cause Riot 400 Bad Request errors.
4. Clean up any warnings or deprecated calls if appropriate.
```

