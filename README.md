<img src="assets/AppIcon-1024.png" width="96" align="right" alt="">

# TokenBar

> Know your AI limits.

A native macOS menu bar app that shows how much AI subscription quota you have
left and when it resets, across Claude Code, Codex and Antigravity.

No setup: every provider is read through the CLI you already have installed and
signed in.

```
CL 16% ⚠
```

`CL` is Claude, `CX` Codex, `AG` Antigravity — the menu bar names whichever
provider is closest to its limit, so the number is never ambiguous about who it
belongs to.

<img src="assets/TokenBar.png" width="320" alt="The TokenBar menu listing Claude, Codex and Antigravity quota windows, each with a bar, the percentage remaining and a reset countdown">

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

Claude and Codex report which plan the account is on, shown as a badge beside
the provider name (`Pro`, `Plus`, `Max`, `Team`…). Claude's comes from
`claude auth status --json`, asked for only after the quota itself parsed, and a
failure there costs the badge rather than the refresh.

Antigravity shows its tier only inside its interactive UI and reports nothing to
a script, so Settings → General has a plan field per provider. Type a plan there
and it becomes that provider's badge; leave it empty to use whatever the
provider reports. A typed label wins over a reported one — you know your own
subscription.

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

The menu lists every enabled provider's quota windows — used and remaining
percentages, a bar, and the reset countdown. Past a certain height the list
scrolls while the header and footer stay pinned, so refresh, settings and quit
stay reachable no matter how many providers are enabled.

Bars read green with half the quota or more left, yellow below that, and red
under 10%. Health is never signalled by colour alone: the percentage, a warning
glyph and the accessibility label all carry it too.

## Settings

- **Providers** — enable or disable each one
- **Refresh** — 1/5/10/15/30 minutes, or manual only (default 5)
- **Menu bar** — the tightest quota across providers (tagged with that
  provider), one chosen provider, or an icon only
- **Plan** — a badge per provider; typed labels win over reported ones
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

## Releasing

Distribution is Developer ID plus notarisation. The Mac App Store is not an
option, because the app is unsandboxed by necessity.

```sh
./scripts/release.sh 1.1.0             # build, notarise, staple, DMG
./scripts/release.sh 1.1.0 --publish   # …and tag and create the GitHub release
```

Two one-off prerequisites:

- a **Developer ID Application** certificate, which needs a paid Apple Developer
  Program membership
- `xcrun notarytool store-credentials tokenbar-notary --apple-id <you> --team-id PPQFDGVAM2`

The version comes from the argument and the build number from the commit count,
so a release edits nothing in the project and the same commit rebuilds
identically. The app is stapled in its own right as well as the DMG, so a copy
dragged out of the disk image still launches on a machine that is offline.

`--skip-notarize` runs everything except the round trip to Apple. It is for
checking the pipeline without a certificate; the result will not run on anyone
else's Mac.

## Adding a provider

Conform to `UsageProvider`, convert the native response into `ProviderUsage`,
and register it in `AppState`. The shared model uses an array of `UsageLimit`
rather than provider-specific fields, so a provider can report zero or more
quota windows of any shape.
