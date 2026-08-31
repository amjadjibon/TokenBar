# TokenBar

> A native macOS menu bar app for tracking AI subscription usage, quotas, remaining capacity, and reset times across multiple providers.

## Overview

TokenBar is a lightweight macOS menu bar utility that gives developers a single place to monitor usage limits across AI coding subscriptions.

Instead of opening multiple dashboards or running provider-specific commands, TokenBar shows the current status of services such as:

- Claude Code
- OpenAI Codex
- Google Antigravity
- Future providers with compatible usage or quota interfaces

The core question TokenBar answers is:

> **How much AI usage do I have left, and when does it reset?**

TokenBar is designed as a local-first macOS utility with no backend service required.

---

## Goals

TokenBar should:

- Show all supported AI subscriptions in one compact menu.
- Display used and remaining quota.
- Display quota reset times.
- Support multiple quota windows per provider.
- Refresh usage automatically.
- Notify the user before a quota is exhausted.
- Detect installed provider CLIs where possible.
- Work without requiring users to manually copy tokens.
- Store usage history locally.
- Make adding new providers straightforward.
- Remain lightweight and feel like a native macOS utility.

---

## Non-Goals

The initial versions of TokenBar will not:

- Proxy AI requests.
- Replace Claude Code, Codex, or Antigravity.
- Manage provider subscriptions.
- Purchase additional credits.
- Scrape provider websites.
- Read browser cookies.
- Depend on undocumented private HTTP APIs.
- Require a TokenBar cloud account.
- Synchronize usage history between machines.

---

## Target Users

TokenBar is primarily for developers who subscribe to multiple AI coding products.

Typical users may have:

- Claude Pro or Max
- ChatGPT Plus, Pro, Business, or another Codex-enabled plan
- Google Antigravity access
- Multiple coding-agent subscriptions at the same time

These users frequently switch providers depending on available quota.

---

# Product Experience

## Menu Bar

TokenBar lives entirely in the macOS menu bar.

Example:

```text
TB 68%
```

The percentage can represent the lowest remaining quota across enabled providers.

Alternative states:

```text
TB 92%
TB 44%
TB 12% ⚠
```

The icon should remain compact and readable.

---

## Main Menu

Example:

```text
┌──────────────────────────────────┐
│ TokenBar                      ↻  │
│                                  │
│ Claude                           │
│ 5 hour          ███████░░  72%  │
│ 28% remaining                    │
│ Resets in 2h 14m                 │
│                                  │
│ Weekly          ████░░░░░  41%  │
│ 59% remaining                    │
│ Resets Friday 4:00 PM            │
│                                  │
│ Codex                            │
│ Weekly          ██████░░░  63%  │
│ 37% remaining                    │
│ Resets Sep 4                     │
│                                  │
│ Antigravity                      │
│ Gemini          ███░░░░░░  31%  │
│ Claude/GPT      ███████░░  76%  │
│                                  │
│ Last updated 18:02               │
│                                  │
│ Settings...                      │
│ Quit TokenBar                    │
└──────────────────────────────────┘
```

---

# MVP

## 1. Menu Bar App

Use SwiftUI's:

```swift
MenuBarExtra
```

TokenBar should not require a Dock icon by default.

---

## 2. Provider Detection

On first launch, TokenBar attempts to detect supported tools.

Examples:

```bash
which claude
which codex
which agy
```

Providers should have one of these states:

```text
Available
Unavailable
Needs Setup
Error
Disabled
```

---

## 3. Usage Dashboard

For every provider, display:

- Provider name
- Plan when available
- Quota name
- Percentage used
- Percentage remaining
- Reset timestamp
- Time until reset
- Last successful refresh

Example:

```text
Claude

5 Hour
Used       61%
Remaining  39%
Reset      2h 14m

Weekly
Used       38%
Remaining  62%
Reset      Fri 16:00
```

---

## 4. Multiple Quota Windows

TokenBar must not assume all providers expose the same quota structure.

A provider can return zero or more limits.

Examples:

```text
5 hour
Daily
Weekly
Monthly
Premium requests
Gemini
Claude/GPT
Credits
```

The data model therefore uses an array rather than provider-specific fields.

---

## 5. Manual Refresh

Users can manually refresh all providers using:

```text
↻ Refresh
```

TokenBar should refresh providers concurrently.

---

## 6. Automatic Refresh

Default:

```text
Every 5 minutes
```

Configurable options:

```text
1 minute
5 minutes
10 minutes
15 minutes
30 minutes
Manual only
```

TokenBar should avoid aggressively invoking provider tools.

---

## 7. Notifications

Users can configure warnings when quota remaining falls below:

```text
20%
10%
5%
```

Example:

```text
Claude weekly quota is below 20%.
```

TokenBar can also notify when quota becomes available after reset.

Example:

```text
Your Codex weekly quota has reset.
```

Use:

```swift
UserNotifications
```

---

# Architecture

TokenBar uses a provider-adapter architecture.

```text
                   ┌─────────────────────┐
                   │      TokenBar       │
                   │       SwiftUI       │
                   └──────────┬──────────┘
                              │
                              ▼
                   ┌─────────────────────┐
                   │   ProviderManager   │
                   └──────────┬──────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
       ClaudeProvider   CodexProvider   AntigravityProvider
              │               │               │
              ▼               ▼               ▼
        Status Line       App Server      Status Line /
          Relay            JSON-RPC        CLI source
```

All providers convert their native response into one common model.

---

# Core Models

## Provider ID

```swift
enum ProviderID: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case antigravity
}
```

---

## Usage Provider

```swift
protocol UsageProvider: Sendable {
    var id: ProviderID { get }

    func isAvailable() async -> Bool
    func fetchUsage() async throws -> ProviderUsage
}
```

---

## Provider Usage

```swift
struct ProviderUsage: Codable, Sendable {
    let provider: ProviderID
    let plan: String?
    let limits: [UsageLimit]
    let updatedAt: Date
}
```

---

## Usage Limit

```swift
struct UsageLimit: Identifiable, Codable, Sendable {
    let id: String

    let name: String

    let usedPercent: Double?
    let remainingPercent: Double?

    let resetAt: Date?

    let metadata: [String: String]?
}
```

Either `usedPercent` or `remainingPercent` may be returned by a provider.

TokenBar can derive the missing value when possible.

---

# Provider Manager

The provider manager coordinates all adapters.

```swift
actor ProviderManager {
    private let providers: [any UsageProvider]

    init(providers: [any UsageProvider]) {
        self.providers = providers
    }

    func refreshAll() async -> [ProviderResult] {
        await withTaskGroup(
            of: ProviderResult.self,
            returning: [ProviderResult].self
        ) { group in
            for provider in providers {
                group.addTask {
                    do {
                        let usage = try await provider.fetchUsage()

                        return .success(usage)
                    } catch {
                        return .failure(
                            provider: provider.id,
                            error: error
                        )
                    }
                }
            }

            var results: [ProviderResult] = []

            for await result in group {
                results.append(result)
            }

            return results
        }
    }
}
```

One provider failing must not prevent others from refreshing.

---

# Claude Integration

Claude Code can expose quota information through its status-line mechanism.

TokenBar should use a small local relay rather than scraping Claude's website.

Architecture:

```text
Claude Code
    │
    │ Status line JSON
    ▼
TokenBar Relay
    │
    ├── Writes latest quota snapshot
    │
    └── Optionally forwards to existing status line
    │
    ▼
TokenBar
```

Example storage:

```text
~/Library/Application Support/TokenBar/providers/claude.json
```

TokenBar reads the latest snapshot and converts it to `ProviderUsage`.

---

## Existing Claude Status Lines

TokenBar should not replace an existing user status-line configuration.

The relay should support chaining:

```text
Claude
  │
  ▼
TokenBar Relay
  │
  ├── capture quota
  │
  └── pipe original input
       │
       ▼
existing statusline script
```

This keeps TokenBar non-invasive.

---

# Codex Integration

Codex should use its local app-server interface rather than browser APIs.

Architecture:

```text
TokenBar
    │
    ▼
Process
    │
    ▼
codex app-server
    │
    │ JSON-RPC / JSONL
    ▼
CodexAppServer actor
    │
    ▼
account/rateLimits/read
```

TokenBar launches the user's installed Codex executable.

It should rely on Codex's existing authentication rather than reading authentication files directly.

---

## Codex App Server Client

Conceptual interface:

```swift
actor CodexAppServer {
    func start() async throws

    func request<T: Decodable>(
        method: String,
        params: Encodable?
    ) async throws -> T

    func stop()
}
```

TokenBar should:

1. Launch the process.
2. Initialize the app-server protocol.
3. Request current rate limits.
4. Parse quota buckets.
5. Convert them into `ProviderUsage`.

---

# Antigravity Integration

Antigravity should follow the same adapter model as Claude.

Preferred sources:

1. Supported status-line quota data.
2. Supported CLI quota output.
3. Additional documented local interfaces if introduced later.

Architecture:

```text
Antigravity
     │
     ▼
TokenBar Relay / CLI adapter
     │
     ▼
AntigravityProvider
     │
     ▼
ProviderUsage
```

Antigravity may expose multiple quota buckets by model family.

TokenBar should preserve these rather than combining them.

Example:

```text
Antigravity

Gemini
Remaining       81%
Reset           3h 10m

Claude / GPT
Remaining       42%
Reset           1h 52m
```

---

# Process Execution

Use Foundation's:

```swift
Process
```

Wrap it behind a reusable actor.

```swift
actor ProcessRunner {
    func run(
        executable: URL,
        arguments: [String]
    ) async throws -> ProcessResult
}
```

Result:

```swift
struct ProcessResult: Sendable {
    let stdout: Data
    let stderr: Data
    let exitCode: Int32
}
```

Never construct shell commands using string concatenation.

Pass arguments directly to `Process`.

---

# Persistence

TokenBar should remain local-first.

Recommended directory:

```text
~/Library/Application Support/TokenBar/
```

Example:

```text
TokenBar/
├── settings.json
├── cache/
│   ├── claude.json
│   ├── codex.json
│   └── antigravity.json
└── history/
    └── usage.jsonl
```

For the MVP, regular JSON is sufficient.

SQLite can be introduced when historical analytics become more important.

---

# Usage History

Each successful refresh can append a snapshot.

Example:

```json
{
  "provider": "claude",
  "limit": "weekly",
  "usedPercent": 48.2,
  "timestamp": "2026-08-31T10:00:00Z"
}
```

History enables future features such as:

- Usage graphs
- Burn rate
- Exhaustion estimates
- Daily usage patterns
- Provider comparison

---

# Burn Rate

A future TokenBar differentiator is predicting when quota will run out.

Example:

```text
Claude Weekly

Quota used       61%
Window elapsed   42%

Burn rate        1.45x

Estimated exhaustion
Wednesday 19:30
```

Simple calculation:

```text
burnRatio =
    quotaUsedFraction /
    windowElapsedFraction
```

Values:

```text
< 1.0     Sustainable

≈ 1.0     On pace

> 1.0     Likely to exhaust early
```

---

# Provider Recommendation

TokenBar could eventually recommend which coding agent has the most available capacity.

Example:

```text
Best available

Codex          83%
Antigravity    61%
Claude         14%

→ Codex
```

The recommendation should remain informational rather than automatically rerouting requests.

---

# Menu Bar Indicator

Several display modes should eventually be supported.

## Lowest Remaining

```text
TB 18%
```

Shows the lowest remaining quota from all enabled providers.

---

## Selected Provider

```text
C 62%
```

Displays one selected provider.

---

## Icon Only

```text
◉
```

Useful for users who prefer minimal menu bars.

---

## Warning State

```text
TB 9% !
```

Shown when one monitored limit crosses the warning threshold.

---

# Settings

Settings should include:

## Providers

```text
[x] Claude
[x] Codex
[x] Antigravity
```

---

## Refresh

```text
Refresh interval
[ 5 minutes ▼ ]
```

---

## Notifications

```text
Notify below

[x] 20%
[x] 10%
[x] 5%

[x] Notify when quota resets
```

---

## Menu Bar

```text
Display

(•) Lowest remaining quota
( ) Selected provider
( ) Icon only
```

---

## Startup

```text
[x] Launch TokenBar at login
```

Use:

```swift
ServiceManagement
```

---

# Privacy

Privacy should be a defining characteristic of TokenBar.

## Principles

TokenBar should:

- Run locally.
- Avoid sending usage information to TokenBar servers.
- Avoid collecting provider credentials.
- Avoid reading browser cookies.
- Avoid extracting authentication tokens.
- Avoid scraping authenticated websites.
- Reuse official provider CLI authentication where possible.
- Store cached usage data only on the local machine.

---

## No Backend Required

The TokenBar MVP should have:

```text
No TokenBar API
No account system
No analytics requirement
No telemetry requirement
No remote database
```

A completely offline TokenBar service should be possible after provider data has been retrieved locally.

---

# Security

Provider adapters should be treated as security-sensitive.

TokenBar should never log:

```text
access tokens
OAuth tokens
session cookies
API keys
authorization headers
```

Logs should contain only diagnostic metadata.

Example:

```text
[Codex] refresh completed
[Claude] snapshot age: 31s
[Antigravity] quota unavailable
```

---

# Error Handling

Provider failures should be isolated.

Example menu:

```text
Claude
72% remaining

Codex
Unable to refresh
Last updated 18 minutes ago

Antigravity
46% remaining
```

TokenBar should continue displaying the last successful value.

---

## Error Types

```swift
enum ProviderError: Error {
    case executableNotFound
    case providerNotConfigured
    case authenticationRequired
    case invalidResponse
    case processFailed(Int32)
    case timeout
    case unavailable
}
```

---

# Stale Data

Snapshots should expose their age.

Possible states:

```text
Fresh       < 10 minutes
Stale       10-30 minutes
Very stale  > 30 minutes
```

UI example:

```text
Codex

54% remaining
Updated 37m ago ⚠
```

---

# Project Structure

Recommended initial repository:

```text
TokenBar/
├── README.md
├── LICENSE
├── TokenBar.xcodeproj
│
├── TokenBar/
│   ├── App/
│   │   ├── TokenBarApp.swift
│   │   └── AppState.swift
│   │
│   ├── Core/
│   │   ├── Models/
│   │   │   ├── ProviderID.swift
│   │   │   ├── ProviderUsage.swift
│   │   │   └── UsageLimit.swift
│   │   │
│   │   ├── Providers/
│   │   │   ├── UsageProvider.swift
│   │   │   └── ProviderManager.swift
│   │   │
│   │   ├── Process/
│   │   │   ├── ProcessRunner.swift
│   │   │   └── ProcessResult.swift
│   │   │
│   │   └── Storage/
│   │       ├── SnapshotStore.swift
│   │       └── SettingsStore.swift
│   │
│   ├── Providers/
│   │   ├── Claude/
│   │   │   └── ClaudeProvider.swift
│   │   │
│   │   ├── Codex/
│   │   │   ├── CodexProvider.swift
│   │   │   ├── CodexAppServer.swift
│   │   │   └── CodexProtocol.swift
│   │   │
│   │   └── Antigravity/
│   │       └── AntigravityProvider.swift
│   │
│   ├── Features/
│   │   ├── MenuBar/
│   │   │   ├── MenuBarView.swift
│   │   │   └── ProviderRow.swift
│   │   │
│   │   ├── Settings/
│   │   │   └── SettingsView.swift
│   │   │
│   │   ├── Notifications/
│   │   │   └── NotificationManager.swift
│   │   │
│   │   └── History/
│   │       └── HistoryStore.swift
│   │
│   └── Resources/
│
├── TokenBarRelay/
│   └── main.swift
│
└── TokenBarTests/
```

---

# Technology Stack

## Language

```text
Swift 6
```

---

## UI

```text
SwiftUI
MenuBarExtra
```

---

## Concurrency

```text
Swift Concurrency
async/await
actors
TaskGroup
```

---

## Process Integration

```text
Foundation.Process
Pipe
FileHandle
```

---

## Startup

```text
ServiceManagement
```

---

## Notifications

```text
UserNotifications
```

---

## Persistence

MVP:

```text
Codable + JSON
```

Later:

```text
SQLite
```

SwiftData is not necessary for the first version.

---

# Refresh Flow

```text
Timer
  │
  ▼
ProviderManager.refreshAll()
  │
  ├── ClaudeProvider.fetchUsage()
  ├── CodexProvider.fetchUsage()
  └── AntigravityProvider.fetchUsage()
  │
  ▼
Normalize ProviderUsage
  │
  ├── Update AppState
  ├── Save cache
  ├── Append history
  └── Evaluate alerts
       │
       ▼
   NotificationManager
```

---

# Refresh Strategy

Providers should refresh concurrently.

Individual provider timeouts should prevent one broken integration from blocking the whole application.

Suggested timeout:

```text
5-10 seconds per provider
```

TokenBar should use cached values when a provider times out.

---

# Launch at Login

Use macOS `ServiceManagement`.

Example direction:

```swift
import ServiceManagement

try? SMAppService.mainApp.register()
```

The setting should be user-controlled.

---

# Keyboard Shortcuts

Potential shortcuts:

```text
⌘R    Refresh
⌘,    Settings
⌘Q    Quit
```

---

# Accessibility

TokenBar should not communicate quota health using color alone.

For example:

```text
72% remaining
18% remaining ⚠
5% remaining !!
```

All usage bars should have accessibility labels.

---

# Logging

Use Apple's unified logging.

```swift
import OSLog

let logger = Logger(
    subsystem: "app.tokenbar",
    category: "providers"
)
```

Avoid `print` for production diagnostics.

---

# Testing

## Unit Tests

Test:

- Percentage normalization
- Remaining quota calculations
- Reset countdowns
- Stale-data detection
- Provider response parsing
- Notification thresholds
- Provider recommendation
- Burn-rate calculations

---

## Fixture-Based Provider Tests

Store sanitized provider responses under:

```text
TokenBarTests/Fixtures/
```

Example:

```text
claude-status.json
codex-rate-limits.json
antigravity-quota.json
```

This makes provider adapters testable without invoking real CLIs.

---

# Future Providers

The architecture should make another integration straightforward.

Example:

```swift
struct GeminiProvider: UsageProvider {
    let id: ProviderID = .gemini

    func isAvailable() async -> Bool {
        // ...
    }

    func fetchUsage() async throws -> ProviderUsage {
        // ...
    }
}
```

Potential future integrations:

- Cursor
- GitHub Copilot
- Gemini CLI
- OpenRouter
- Windsurf
- Zed AI
- JetBrains AI
- Local model servers
- API credit balances

Only add integrations when there is a reasonable supported mechanism for retrieving quota data.

---

# Roadmap

## v0.1 — Core MVP

- macOS menu bar application
- Claude integration
- Codex integration
- Antigravity integration
- Used/remaining percentage
- Reset countdown
- Manual refresh
- Automatic refresh
- Cached values
- Provider error states

---

## v0.2 — Alerts

- Configurable warning thresholds
- macOS notifications
- Reset notifications
- Launch at login
- Provider enable/disable settings

---

## v0.3 — History

- Usage history
- Daily usage
- Weekly charts
- Burn-rate calculation
- Estimated quota exhaustion

---

## v0.4 — Smart Capacity

Add:

```text
Best provider right now
```

Rank providers by usable remaining capacity.

Potential inputs:

- Remaining quota
- Time until reset
- Burn rate
- Provider availability

---

## v0.5 — Extensibility

Possible provider plugin model.

Example:

```text
~/Library/Application Support/TokenBar/providers/
```

A provider integration could eventually expose a small JSON contract.

This should only be added if maintaining many providers starts making the main application cumbersome.

---

# Implementation Milestones

## Milestone 1 — Shell

Build the smallest native application.

Deliver:

- `MenuBarExtra`
- Static provider rows
- Settings window
- Quit action

---

## Milestone 2 — Domain Model

Implement:

- `ProviderID`
- `ProviderUsage`
- `UsageLimit`
- `UsageProvider`
- `ProviderManager`

Use mock providers before integrating external tools.

---

## Milestone 3 — Codex

Implement:

- Codex executable detection
- App-server lifecycle
- JSON-RPC transport
- Rate-limit parsing
- Error handling
- Fixtures/tests

Codex is a good first real provider because it can use a structured local integration.

---

## Milestone 4 — Claude

Implement:

- Status-line relay
- Snapshot storage
- Existing status-line chaining
- Claude provider parser
- Setup flow

---

## Milestone 5 — Antigravity

Implement:

- Antigravity detection
- Quota-source integration
- Model quota normalization
- Fixtures/tests

---

## Milestone 6 — Persistence

Implement:

- Last successful snapshot
- Settings
- Refresh interval
- Provider enable/disable state

---

## Milestone 7 — Notifications

Implement:

- Threshold evaluation
- Deduplication
- Reset detection
- Notification permissions

---

## Milestone 8 — Release

Prepare:

- App icon
- Code signing
- Notarization
- DMG or ZIP distribution
- GitHub Releases
- Homebrew Cask if appropriate

---

# Suggested Development Order

Start with:

```text
1. MenuBarExtra UI
2. Mock UsageProvider
3. ProviderManager
4. Codex integration
5. Local caching
6. Claude relay
7. Antigravity integration
8. Notifications
9. History
10. Burn-rate predictions
```

Do not start with historical analytics or charts.

The key technical risk is provider data retrieval, so provider adapters should be validated before expanding the interface.

---

# Product Principles

TokenBar should remain:

### Local

Usage data stays on the user's Mac.

### Small

It should feel like a utility rather than a dashboard application.

### Fast

Opening the menu should be instant and use cached data while refreshing in the background.

### Provider Agnostic

The domain model should not encode assumptions specific to Claude, Codex, or Antigravity.

### Non-Invasive

TokenBar should integrate with existing provider tooling without breaking existing configuration.

### Transparent

Users should be able to see where each quota value came from and when it was last refreshed.

---

# Possible Taglines

```text
Know your AI limits.
```

```text
Your AI quota, at a glance.
```

```text
One bar for every AI limit.
```

```text
Keep an eye on your AI usage.
```

```text
See what's left before the reset.
```

---

# License

Choose based on the intended distribution model.

For a fully open-source utility:

```text
MIT
```

or:

```text
Apache-2.0
```

If commercial features are planned later, the provider architecture and core utility can still remain open source while optional advanced functionality is distributed separately.

---

# Summary

TokenBar is a native macOS menu bar utility that aggregates AI subscription quotas into one compact interface.

The initial product should focus on three things:

1. **Reliable provider integrations**
2. **Fast visibility into remaining quota**
3. **Reset and low-quota alerts**

The first release should stay deliberately small.

The long-term opportunity is turning simple quota visibility into a useful **AI capacity dashboard** that can answer not only:

> How much quota do I have left?

but eventually:

> Which AI provider should I use right now?
