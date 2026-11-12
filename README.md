# Otto

Otto is a personal operating system for the AI agents that work for you. It's a native
macOS app: **Home** is where your day starts (a daily brief, pinned cards and a composer), and
**Chat** holds your sessions, bots and teams beside Documents, Dashboards, Automations and a
built-in browser. You bring your own agents (Claude Code, Codex, Cursor, Grok, Hermes and others)
and your own accounts. Otto runs them locally and keeps your files, memory and credentials on
your Mac.

- **Website and downloads:** <https://openotto.io>
- **Changelog:** [CHANGELOG.md](CHANGELOG.md)

## Features

- Home with a daily brief and pinned cards, and Chat for sessions, bots and teams
- Documents, Dashboards, Automations and a built-in browser your agents can use
- Chat sessions and saved bots with their own memory, teams and subagents
- Provider CLIs run in real PTYs, with model and account switching per agent
- One typed tool registry exposed to agents over MCP and to you through `ottoctl`
- Separate Work and Personal profiles, each with its own memory and bots
- Optional realtime voice control, using your own xAI key
- A mobile companion app that pairs with your Mac

## Build from source

You need macOS 15 or newer and Xcode 26 or newer (Swift 6.2). You don't need an Apple
Developer account.

```sh
git clone https://github.com/maxtrigify/Otto.git
cd Otto
swift run Otto
```

For day-to-day development, install **Otto Dev**, an app in `~/Applications` that rebuilds
and relaunches itself when sources change:

```sh
scripts/dev-app.sh reload
```

It creates a local self-signed signing identity the first time it runs. Build logs go to
`~/Library/Logs/Otto/dev-reloader.log`.

## Intel and Apple silicon builds

The macOS packaging script builds **both x86_64 (Intel) and arm64 (Apple silicon)**,
then combines the app and every bundled helper into a universal application. Both
architectures require macOS 15 or newer; building requires Xcode 26 / Swift 6.2.
An Intel Mac does not need Rosetta.

```sh
OTTO_VERSION=0.2.17 scripts/package-macos.sh
OTTO_VERSION=0.2.17 scripts/verify-release.sh
```

The ZIP is written to `.build/distribution/Otto-0.2.17.zip`, with a SHA-256 file.
Packaging compiles both architectures and ad-hoc-signs the result by default.
Verification checks both CPU slices and executes helper smoke tests on the host.
It does not notarize the app. The existing DMG script uses this same universal ZIP.

For a native Intel development build only:

```sh
scripts/otto-swift build -c release --arch x86_64 --jobs 2
```

The macOS CI matrix validates on Intel and Apple silicon and uploads universal ZIPs
named `Otto-universal-tested-x86_64` and `Otto-universal-tested-arm64`.
Passing CI is required before treating a new package as validated on both CPUs.
Previously published upstream releases are unchanged and may still be ARM-only.

The pinned optional **Parakeet** and **Whistle** installers currently ship ARM-only
speech engines. On Intel they report that limitation before downloading; choose
another transcription provider. This does not disable the rest of Otto.

## Test

```sh
swift build
swift test --no-parallel
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
swift build -c release -Xswiftc -warnings-as-errors
```

The suite runs serially because several suites use process-wide PTY and child-process
facilities. It never makes paid voice or model calls. Provider launch tests only run when
the matching CLI (Claude Code, Codex, Cursor, Kimi, OpenCode, Grok or Hermes) is installed.

## Repository layout

| Path | What's there |
|---|---|
| `Sources/OttoApp` | The macOS app (SwiftUI) |
| `Sources/OttoCore`, `OttoModels`, `OttoPersistence` | Canvas model, commands and SQLite persistence |
| `Sources/OttoRuntime`, `OttoHarness` | Agent supervision and provider harnesses |
| `Sources/OttoMCP`, `otto-mcp`, `ottoctl` | MCP server and command-line control |
| `Sources/ottod` | Headless host daemon |
| `Apps/OttoMobileApp` | iOS companion app |
| `Web` | Bundled diagram runtimes |
| `docs/ADR` | Architecture decision records |
| `docs/THREAT_MODEL.md` | Security model |

## Privacy and security

Otto has no public inbound port. Credentials are stored only in the macOS Keychain, and
content from tools and the web is treated as data, never as authorization. See
[SECURITY.md](SECURITY.md) to report a vulnerability.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Please follow the
[code of conduct](CODE_OF_CONDUCT.md).

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE). The Otto name and logo
are covered by the [trademark policy](TRADEMARKS.md). Third-party components
are listed in [packaging/THIRD_PARTY_NOTICES.md](packaging/THIRD_PARTY_NOTICES.md).
