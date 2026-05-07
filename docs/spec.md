# Relay — Spec

Slack ↔ SMS bridge.

## Goal
A menu-bar macOS app that forwards selected Slack messages to your phone via SMS, and routes SMS replies back into Slack. Lets the user respond without installing Slack on the phone.

## Scope

**In:**
- Single corporate Slack workspace, single user
- Watch list: channels (all root messages) + users (all DMs from them)
- Mention detection: `@you` in threads of watched channels
- SMS via Twilio (US local number, polling for inbound)
- Bidirectional: SMS reply → Slack post (in same thread if applicable)
- Implicit reply target = last received SMS; prefix shorthand to target older
- Global pause toggle
- Plaintext markdown passthrough; resolve `<@U…>`/`<#C…>` to display names
- Multi-segment SMS for long messages
- Ignore edits/deletes/reactions

**Out (v1):**
- Multiple workspaces
- Quiet hours, digest/batching
- File previews (just `[file: name.pdf]`)
- Reply-from-SMS to non-Slack people
- Distribution to other users

## Architecture

```
┌─────────────────────────────────────────┐
│  macOS app (SwiftUI, menu-bar only)     │
│  ┌──────────────┐    ┌───────────────┐  │
│  │ Slack client │    │ Twilio client │  │
│  │  (Socket     │    │  (poll every  │  │
│  │   Mode WS)   │    │   30s)        │  │
│  └──────┬───────┘    └───────┬───────┘  │
│         │                    │          │
│         └────► Router ◄──────┘          │
│                  │                      │
│      ┌───────────┼──────────┐           │
│      │           │          │           │
│   Settings   Keychain   App Support     │
│   window     (tokens)   (state.json)    │
└─────────────────────────────────────────┘
        │                       │
        ▼                       ▼
   Slack API              Twilio REST API
```

Single process. No external infra. Slack inbound is push (Socket Mode WS), Twilio inbound is pull (polling). Both outbound paths are direct REST calls.

## Slack integration

**App setup (one-time, requires admin install):**
- Custom Slack app in workspace
- Socket Mode enabled → app-level token (`xapp-…`)
- Bot token scopes: `channels:history`, `groups:history`, `im:history`, `mpim:history`, `users:read`, `chat:write`, `channels:read`, `groups:read`, `im:read`
- User token scopes: `chat:write` (so replies post as *you*, not a bot)
- Subscribed bot events: `message.channels`, `message.groups`, `message.im`, `message.mpim`

**TBD:** Posting replies as the user requires user token. Receiving DM events likely also needs user-token subscriptions (`message.im` with user scope) since the bot can't be a participant in your DMs. Confirm during build that bot-token DM events flow when the user installs the bot — if not, add user-token event subscription.

**Inbound (Slack → SMS):**
- Connect to Socket Mode WS on launch, auto-reconnect on drop
- For each `message` event:
  - If channel is in watchlist:
    - If `thread_ts` absent or equals `ts` (root message): forward
    - Else (thread reply): forward only if text contains `<@SELF_USER_ID>`
  - If channel is a DM and counterparty is in user-watchlist: forward
  - Otherwise: drop
- Format for SMS: `[#channel-name from-display-name] message text`
  - DMs: `[DM from-display-name] …`
  - Resolve `<@U…>` and `<#C…>` to names (cache user/channel lookups)
  - Strip `<>` link wrappers; keep raw URL
  - Markdown passes through as-is (`*bold*` → `*bold*`)
  - File-only messages → `[file: filename.ext]`
  - Append routing token (see below)

**Outbound (SMS → Slack):**
- Post via `chat.postMessage` with user token
- If the source message was a thread reply, set `thread_ts` to the parent's `thread_ts`
- If the source was a channel root: post as a thread reply to that root (so SMS replies don't clutter the channel as new top-level posts)
  - **TBD:** confirm this is the desired behavior — it's safer (less noisy in channels) but means you can't SMS-reply with a brand-new top-level message. Likely fine.
- DMs: post directly to the IM channel

## Twilio integration

**Number:** US local, ~$1.15/mo + $0.0079/outbound SMS, $0.0075/inbound. Throughput limit ~1 SMS/sec — fine for this use case.

**Configuration:**
- Leave the number's webhook URL blank
- All inbound delivery via polling

**Inbound polling:**
- Every 30s: `GET /Messages.json?To=<your-number>&PageSize=50` (sorted desc by date)
- Filter to messages newer than `last_seen_date`, dedup against a small in-memory ring buffer of recent SIDs
- Update `last_seen_date` to newest message's `date_sent`
- On startup, set `last_seen_date` to "now" — don't replay the entire SMS history

**Outbound:**
- `POST /Messages.json` with `From=<your-number>`, `To=<your-phone>`, `Body=...`
- Multi-segment: just send the full body, Twilio handles segmentation (each segment billed separately)
- Hard cap at e.g. 1500 chars / 10 segments to avoid runaway cost on a giant Slack paste

## Reply addressing scheme

Every outbound SMS gets a short suffix token: `[3]`. Counter increments per outbound message, wraps at 999.

State per token: `{token → (slack_channel_id, slack_thread_ts_or_root_ts, source_message_ts)}`. Keep last 200 tokens; older entries fall off (replying to a 3-day-old SMS is a non-goal).

**Reply parsing:**
- `text` (no prefix) → reply to most recent received SMS
- `3: text` or `[3] text` → reply to message tagged `[3]`
- `3 text` (no colon) → also accepted; if first whitespace-separated token is a number ≤999 and matches an active token, treat as target
- Unknown token → SMS error reply: `unknown msg id 3`

**Edge case:** if you SMS a number that doesn't match any active token, error back. If you SMS before any inbound SMS exists (no current target), error back.

## Settings UI

Single window, three tabs:

1. **Connections**
   - Twilio: Account SID, Auth Token, From number, Your phone number
   - Slack: app-level token (`xapp-`), bot token (`xoxb-`), user token (`xoxp-`)
   - Test buttons: "send test SMS", "test Slack connection"
   - Status indicators: Slack WS (green/red), Twilio poll (last success time)

2. **Channels** — fetched from Slack on open
   - Searchable list with checkboxes
   - Sections: Public channels, Private channels, DMs (separate users tab? or unified?). Probably unified with type icon.
   - **TBD:** for DM watching, you toggle the *user*, not the IM channel. Render as a separate "Direct messages from" picker that uses `users.list`.

3. **Behavior**
   - Pause toggle (also accessible from menu bar)
   - **TBD:** anything else for v1? Auto-start at login toggle.

## State and storage

**Keychain** (`Security.framework`):
- Twilio Account SID + Auth Token
- Slack app-level, bot, user tokens

**`~/Library/Application Support/<bundle-id>/state.json`:**
- `last_seen_twilio_date`
- Watched channel IDs + user IDs
- Self user ID (resolved once at first connect)
- Active routing tokens map (last 200)
- Pause flag

**In-memory:**
- User/channel name cache (TTL ~1h)
- Recent SID ring buffer for dedup
- Slack WS connection state

## Menu bar

Status icon states:
- Normal: monochrome SF Symbol (e.g. `bubble.left.and.bubble.right`)
- Paused: same with a slash overlay
- Error: red dot badge

Click menu:
- Status line: "Connected" / "Slack disconnected" / "Twilio polling failed at HH:MM"
- Pause / Resume toggle
- Open settings…
- Quit

## Lifecycle and reliability

- `LSUIElement = true` (no dock icon, no main window on launch)
- Auto-start at login via `SMAppService.mainApp.register()`
- Slack WS reconnect: exponential backoff, capped at 60s
- Twilio polling: skip-and-retry on transient errors, surface persistent failure in menu bar
- Sleep/wake: WS will drop on sleep, reconnect on wake; polling resumes from `last_seen_date` and catches up
- All errors logged to `~/Library/Logs/<bundle-id>/app.log` (rotated)

## Open questions to resolve before/during build

1. **DM event delivery:** does subscribing to `message.im` with bot token actually deliver events for DMs the user receives? If not, need user-token event subscription.
2. **Reply-as-thread-reply for channel root messages:** confirm this is desired behavior (safer, less channel noise) vs. allowing SMS to post brand-new top-level messages.
3. **Channel/user picker UI:** unified list or separate tabs for "channels to watch" vs "users whose DMs to watch"?
4. **Bundle / signing:** Developer ID signed + notarized for distribution to your own Mac, or unsigned with `xattr -d com.apple.quarantine` workflow? (Affects build setup, not runtime.)
