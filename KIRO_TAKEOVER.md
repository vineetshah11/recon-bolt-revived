# 🚨 KIRO ORCHESTRATOR TAKEOVER PROTOCOL

> **NOTE FOR KIRO**: If you are reading this file, you are now operating as the **CHIEF ORCHESTRATOR & LEAD ENGINEER** for the Recon Bolt Revival project. Antigravity may be on standby or out of quota. You have full ownership of git, CI monitoring, IPA building, code reviews, and directing other agents.

---

## 1. PROJECT RECAP & STATE

* **Project**: Reviving **Recon Bolt** (iOS Valorant Companion App, iOS 16+, SwiftUI).
* **Work Location**: `d:\Hobbies\AI\Antigravity Projects\Recon Bolt\test-dt-clone`
* **Submodule**: `d:\Hobbies\AI\Antigravity Projects\Recon Bolt\ValorantAPI-repo`
* **Clean Quick-Access Source Directory**: `d:\Hobbies\AI\Antigravity Projects\Recon Bolt\Recon-Bolt-Source-Files`
* **Latest Generated IPA**: `d:\Hobbies\AI\Antigravity Projects\Recon Bolt\build-output\ReconBolt-ipa\ReconBolt.ipa`
* **GitHub Repository**: `https://github.com/vineetshah11/recon-bolt-revived` (`main` branch)
* **GitHub PAT**: `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`

---

## 2. RECENT COMMITS & COMPLETED WORK (DO NOT REDO)

* `5032636`: **Kiro Fix**: Injected `assetManager` in `ContentView`, revealed scoreboard names with `.anonymizing(additionally: .none)`, bypassed own-user anonymization in `PlayerIdentityCell`, and fixed Tier 0 "Unranked" display in `CompetitiveSummaryCell`.
* `fc9babd`: Handled loadout 404 silently, improved `AssetsUnwrappingView`, made queue asset fetch non-fatal.
* `ab8b9f6`: SessionHandler marks `session.hasExpired = true` on resumption failure to prompt re-login.
* `b8a0d5d`: Redesigned `StoreDetailsView` with 2x2 grid, Valpaw dark theme, ticking countdown.
* `30684dc`: Restyled `MatchCell` to dark aesthetic.

---

## 3. ACTIVE AGENT DELEGATION ROSTER (WHAT EACH AI IS WORKING ON)

Kiro, here is the current live assignment matrix so you know exactly who owns what and where work is coming from:

| Agent | Platform / Access | Active Assignment Assigned | Next Deliverable to Expect | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Agent #3: Freebuff Coder** | Local IDE / Editor | Implementing `nightMarketView(for:)` in `StoreDetailsView.swift` with dark Valorant cards | Drop-in Swift code for `nightMarketView` | 🔵 **Working** |
| **Agent #7: Free ChatGPT** | Chat UI (No files) | Designing native SwiftUI Charts for `StatisticsView.swift` (Win Rate, KDA, Headshot %) | SwiftUI View structs for stats cards | 🔵 **Working** |
| **Agent #4: Free Claude 1** | Chat UI (No files) | Auditing `MatchListView.swift` for pagination & pull-to-refresh edge cases | Logic analysis / edge case report | ⚪ **Standby** |
| **Agent #5: Free Claude 2** | Chat UI (No files) | Reviewing `ScoreboardView.swift` layout constraints & row sizing | Layout recommendations | ⚪ **Standby** |
| **Agent #8: Gemini Plus** | Web / Chat | Cross-referencing current Act/Episode IDs & validating API schemas | Endpoint schema stability report | ⚪ **Standby** |
| **Agent #9: Meta AI / Muse**| Chat UI (No files) | Rewriting technical error dialogs & About screen copy into gamer-friendly text | Copy strings for alert dialogs | ⚪ **Standby** |
| **Agent #6: Claude Pro** | ⚠️ Paid Overage | 🛑 **DO NOT ASSIGN ROUTINE TASKS** (Account has billable overage enabled) | **Emergency reserve only** | 🔒 **LOCKED** |

---

## 🚨 MANDATORY COMPLETION RULE: YOU ARE NOT DONE UNTIL THE NEW IPA IS IN BUILD-OUTPUT!

> ⚠️ **CRITICAL WARNING FOR KIRO**: 
> You have previously committed and pushed code to `main` **WITHOUT updating the `.ipa` file**. 
> The user **cannot** test your code on their iPhone without the fresh IPA! Pushing code to GitHub is only Step 1.
> **EVERY SINGLE TASK IS INCOMPLETE UNTIL THE FRESH IPA IS DOWNLOADED TO `build-output\ReconBolt-ipa\ReconBolt.ipa`!**

To make this foolproof, an automated script has been created: `update-ipa.ps1`.
**Right after you run `git push origin main`, you MUST execute:**
```powershell
powershell -ExecutionPolicy Bypass -File .\update-ipa.ps1
```
This script will automatically:
1. Wait for GitHub Actions to finish building.
2. Verify the build succeeded.
3. Automatically delete the old IPA and download the new one.
4. Print the exact timestamp and file size of the new `ReconBolt.ipa`.

---

## 4. YOUR EXACT CYCLE FOR EVERY TASK

Whenever you make an edit or apply code from other agents:

```powershell
$git = "C:\Users\Vineet\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd\git.exe"

Set-Location "d:\Hobbies\AI\Antigravity Projects\Recon Bolt\test-dt-clone"

# 1. APPLY & STAGE
& $git add -A
& $git commit -m "feat/fix: <detailed description of the change>"

# 2. PUSH TO TRIGGER GITHUB ACTIONS CI
& $git push origin main

# 3. MANDATORY: RUN THE AUTOMATED IPA FETCHER (DO NOT SKIP!)
powershell -ExecutionPolicy Bypass -File .\update-ipa.ps1

# 4. SYNC QUICK-ACCESS FOLDER
# If any file in Shared/ or ValorantAPI/ was edited, copy the updated version to:
# d:\Hobbies\AI\Antigravity Projects\Recon Bolt\Recon-Bolt-Source-Files\
```

---

## 5. IMMEDIATE BACKLOG (WHAT TO INTEGRATE NEXT)

1. **Night Market Redesign (`StoreDetailsView.swift`)**:
   - Freebuff is working on this. When user provides the snippet, replace `nightMarketView(for:)` in `StoreDetailsView.swift`, verify build, and push.
2. **Statistics Screen Visual Charts (`StatisticsView.swift`)**:
   - ChatGPT is designing the charts. When user provides the views, wire them into `StatisticsView.swift`.
3. **Reference Tab Modernization (`ReferenceView.swift`, `MapListView.swift`, `AgentListView.swift`)**:
   - Modernize the plain list views with grid cards.
4. **Error Message & Copy Polish**:
   - Integrate Muse's friendlier alert messages.

---

## 6. AGENT COORDINATION RULES FOR KIRO

* **Agent #6 (Friend's Claude Pro)**: ⚠️ **DO NOT USE** unless completely deadlocked on an unresolvable compiler failure. The owner has overage billing turned on.
* **Always check `AGENT_MISSION_CONTROL.md`**: Update task statuses when completing a feature.
