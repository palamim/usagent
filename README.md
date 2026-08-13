# usagent

A macOS menu bar app that shows Claude subscription usage at a glance.

![usagent demo](docs/demo.gif)

No dock icon, no settings, no telemetry. Reads the OAuth token Claude
Code already stores in your Keychain and calls Anthropic's usage
endpoint directly.

## Build & run

```sh
make run     # swift run, for development (dock icon flashes briefly — expected, see below)
make app     # builds usagent.app with a proper Info.plist (no dock icon)
make open    # builds and opens usagent.app
```

## Run at login

There's no installer. Build the app once, then add it to Login Items:

1. `make app`
2. Move (or leave) `usagent.app` wherever you want it to live permanently
   — System Settings will reference that path.
3. **System Settings → General → Login Items & Extensions → Open at
   Login → +** → select `usagent.app`.

Rebuilding overwrites the same path, so once it's added as a login item
you don't need to re-add it after `make app` again.

## First launch: Keychain prompt

The OAuth token lives in the macOS Keychain under the service name
`Claude Code-credentials`, created by the Claude Code CLI — not by this
app. The first time usagent reads it, macOS will prompt for your login
password to authorize access. **Click "Always Allow"** (not "Allow") —
otherwise you'll be prompted again on every launch or every refresh.

If you're prompted repeatedly even after that, the Keychain item's ACL
may have been reset (e.g. after rebuilding with a different code
signature). Re-authorizing once with "Always Allow" fixes it again.

## Why direct API calls, not a companion state file

[Claude-Code-Usage-Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor)
invites native menu bar apps to consume its `--write-state` output
instead of calling Anthropic's endpoint directly. We call the endpoint
directly instead: its own "official" data source for that state file is
the same OAuth usage endpoint (behind an opt-in `--api` flag), so
routing through it would mean running a separate Python tool as a
background process for no benefit — just a dependency and a moving
part this app doesn't need.

## Notes

- The endpoint (`https://api.anthropic.com/api/oauth/usage`) is
  undocumented. It could change or disappear without notice.
- On a Pro plan, only the `five_hour` and `seven_day` fields in the
  response are populated; several other fields (Opus-specific limits,
  spend/credits) are Max-only or unused and are ignored.
- Refreshes on a 60s timer and on click, throttled to at most once per
  15s to avoid hammering the endpoint.
