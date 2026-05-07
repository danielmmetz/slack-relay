# SMS consent

This document describes the SMS opt-in flow for Relay, a personal Slack-to-SMS bridge. It is the consent reference URL provided to Twilio for toll-free verification.

## Service description

Relay is a single-user macOS menu-bar app. It forwards messages from a Slack workspace the operator belongs to (watched channels, watched users' direct messages, and `@you` mentions in threads) to the operator's own mobile phone via SMS, and routes SMS replies back to the originating Slack thread.

The service is not distributed and has no public sign-up. The only recipient of any SMS sent by this service is the operator who installed and configured the app.

## Opt-in flow

1. The operator builds and installs the app on their own Mac.
2. On first launch, the operator opens the Settings window and enters:
   - Their own Twilio Account SID, Auth Token, and Twilio "From" number.
   - Their own mobile phone number as the SMS destination.
   - Their own Slack tokens for the workspace they belong to.
3. By entering their own phone number into the destination field and saving the settings, the operator consents to receive SMS from the Twilio number they themselves provisioned.

There is no third-party recipient and no web-based opt-in form, because the operator and the recipient are the same person.

## Message volume and content

- Estimated volume: under 100 messages per day, typically far less.
- Content: forwarded Slack messages, formatted as `[#channel from-name] message text [N]` where `[N]` is a short routing token used for reply addressing. DMs use `[DM from-name] …`. File-only messages render as `[file: filename.ext]`.
- Sample message: `[#eng-oncall from alice] deploy failed on prod-2, can you check? [3]`

## Opt-out

Standard carrier keywords are honored. Replying `STOP` to the Twilio number triggers Twilio's built-in unsubscribe, which blocks further outbound messages from that number to the operator's handset. The operator can also disable forwarding at any time from the menu-bar Pause toggle, or quit the app.

`HELP` returns a short message identifying the service and pointing to this document.

## Contact

Operator contact for questions about this service: see the GitHub repository this document lives in.
