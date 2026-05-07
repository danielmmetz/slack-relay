# Relay

A menu-bar macOS app that bridges Slack and SMS for a single user. Forwards selected Slack messages (watched channels, watched users' DMs, and `@you` mentions in threads) to your phone via Twilio, and routes SMS replies back to the originating Slack thread.

The use case: respond to important Slack traffic without installing Slack on your phone.

## Status

Personal project. Single workspace, single operator, single recipient phone number. Not distributed.

## How it works

Single macOS process. Slack inbound is push (Socket Mode WebSocket); Twilio inbound is pull (polling every 30s). Both outbound paths are direct REST. Tokens live in Keychain; small state file in `~/Library/Application Support`.

See [docs/spec.md](docs/spec.md) for the full design.

## Build

Requires [xcodegen](https://github.com/yonaskolb/XcodeGen).

```
make run     # generate project, build Release, install to /Applications, launch
make build   # build only
make clean   # nuke generated project + build dir
```

First launch: open Settings from the menu-bar icon and fill in the Twilio and Slack credentials (see [docs/spec.md](docs/spec.md) for required Slack scopes).

## SMS consent and Twilio toll-free verification

This service sends SMS only to the operator's own phone number, entered by the operator in the app's Settings window. See [docs/consent.md](docs/consent.md) for the full opt-in description used for Twilio toll-free verification.
