# TokenBar

> Know your AI limits.

A native macOS menu bar app that shows how much AI subscription quota you have
left and when it resets, across Claude Code, Codex and Antigravity.

No setup: every provider is read through the CLI you already have installed and
signed in.

```
TB 15% ⚠
```

Everything runs locally. There is no TokenBar account, no backend, and no
telemetry. TokenBar never collects provider credentials, reads browser cookies,
or scrapes provider websites — it reuses the authentication your existing CLIs
already have.

## Requirements

macOS 26.5 or later.

## Providers

| Provider | Source | Setup |
| --- | --- | --- |
| Claude | `claude -p "/usage"` | None — uses your installed `claude` |
| Codex | `codex app-server` → `account/rateLimits/read` | None — uses your installed `codex` |
| Antigravity | `agy -p "/usage"` | None — uses your installed `agy` |

Claude and Codex also report which plan the account is on, shown as a badge
beside the provider name (`Pro`, `Plus`, `Max`, `Team`…). Claude's comes from
`claude auth status --json`, asked for only after the quota itself parsed, and a
failure there costs the badge rather than the refresh. Antigravity exposes no
plan or tier through its CLI, so it shows none.

### Claude

Nothing to configure. TokenBar runs:

```sh
claude -p "/usage" --output-format json
```

Claude Code renders that report locally — zero turns, zero tokens, zero cost —
so polling it does not consume the quota it reports on.

The report is prose, so TokenBar parses the `Current …:` lines out of it:

```
Current session: 36% used · resets Sep 1 at 2:29am (Asia/Kuala_Lumpur)
Current week (all models): 5% used · resets Sep 6 at 10:59pm (Asia/Kuala_Lumpur)
```

Everything else in the report is ignored, so changes elsewhere cannot break it,
and a line whose reset stamp is unreadable still contributes its percentage. If
Claude Code ever changes those lines, TokenBar shows an error rather than a
stale or wrong number.

Quota appears for Claude subscription accounts. An API-key account gets a report
with no quota lines, and TokenBar reports the provider as unavailable.

### Antigravity

Nothing to configure. TokenBar runs:

```sh
agy -p "/usage" --output-format json
```

Also free to poll — zero turns, zero tokens.

Antigravity reports structured JSON rather than prose, and splits its limits by
model family. TokenBar keeps that split rather than averaging it, because the
family about to run out is the one worth knowing about:

```
Gemini 5 hour            42% left
Gemini Weekly            81% left
Claude and GPT 5 hour     7% left   ← the one that actually limits you
Claude and GPT Weekly   100% left
```

Fractions are reported as `0...1` and converted to percentages.

## Menu

The menu lists every enabled provider's quota windows. Past a certain height the
list scrolls while the header and footer stay pinned, so Refresh, Settings and
Quit are always reachable no matter how many providers are enabled.

## Settings

- **Providers** — enable or disable each one
- **Refresh** — 1/5/10/15/30 minutes, or manual only (default 5)
- **Menu bar** — lowest remaining quota, one selected provider, or icon only
- **Notifications** — warn below 20%, 10% and/or 5%, and when a quota resets
- **Startup** — launch at login

Warnings fire once per quota window, at the tightest threshold crossed. Reset
notices are only sent for a quota you were actually warned about.

## Where things live

```
~/Library/Application Support/TokenBar/
├── settings.json
├── cache/              # last successful reading per provider
└── history/usage.jsonl # appended when a quota actually changes
```

TokenBar reads no other files. Every provider is queried through its own CLI.

## Sandboxing

TokenBar runs outside the macOS app sandbox. It has to: it launches your own
`claude`, `codex` and `agy` binaries, which read credentials and config from
your home directory. That does not work from inside a sandbox container. The hardened
runtime stays enabled.

## Development

```sh
xcodebuild -project TokenBar.xcodeproj -scheme TokenBar build
xcodebuild -project TokenBar.xcodeproj -scheme TokenBar \
  -destination 'platform=macOS' test -only-testing:TokenBarTests
```

Provider adapters are tested against sanitized fixtures in
`TokenBarTests/Fixtures/`, so no real CLI is invoked.

## Adding a provider

Conform to `UsageProvider`, convert the native response into `ProviderUsage`,
and register it in `AppState`. The shared model uses an array of `UsageLimit`
rather than provider-specific fields, so a provider can report zero or more
quota windows of any shape.
