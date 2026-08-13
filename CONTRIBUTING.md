# Contributing

## PR guidelines

- **One change per PR.** A PR that bundles a bug fix with an unrelated
  feature (or several unrelated features) won't get approved as one
  unit — split it up, even if it was all written in one sitting.
- **Keep PRs small.** This app is deliberately small — a few hundred
  lines across five source files. A PR that grows it substantially is
  a sign the change should be scoped down or split, not a sign the app
  needed to grow that much.

## The most useful contribution right now

**Verify `seven_day_opus` against a real Claude Max account.** This
app is built and tested against Pro only. The weekly Opus sub-cap
field (`seven_day_opus` in the endpoint response) is handled
defensively — shown as an extra "Weekly Opus" row and folded into the
"closest to limit" calculation when present — but nobody has confirmed
its actual shape or behavior on Max. If you have Max access:

1. Read your OAuth token from the Keychain and hit
   `https://api.anthropic.com/api/oauth/usage` directly with it — see
   `Sources/usagent/UsageClient.swift` for the exact headers.
2. Share the **redacted** JSON response (strip the token and org UUID)
   in an issue. Does `seven_day_opus` look like `five_hour`/
   `seven_day`? Does it behave the way [Plan support](README.md#plan-support)
   describes?
3. If it doesn't, that's the bug report. If it does, that's
   confirmation we can drop the "not verified" caveat from the README.

## Build

```sh
swift build
swift test    # requires full Xcode.app, not just the Command Line Tools
make app      # builds usagent.app
```

## Everything else

Open an issue for bugs or ideas. If a change touches the Keychain read
or the usage endpoint call, say what you tested it against (plan tier,
macOS version) — those are the parts most sensitive to account and
environment differences.
