# Claude Design prompt — Herdr iOS

Attach `docs/design/reference-desktop.png` (the Herdr desktop app) with this prompt.

---

Design a native iOS/iPadOS app (SwiftUI, iOS 26 conventions) called **Herdr** — a mobile client for Herdr, a terminal workspace where AI coding agents (Claude Code, Codex, Pi, OpenCode…) run on the user's always-on Mac. The phone connects to that Mac over Tailscale + SSH and shows the same spaces, tabs and agents as the desktop app.

**The core job:** an agent stops and waits for the user. The user gets a notification, taps it, reads what the agent asked, and replies — in under 20 seconds, one-handed. Everything else is secondary. The user reads and sends replies; they rarely type key by key.

## Visual direction

Match the attached desktop screenshot closely: it is the source of truth for the look.
- Dark, quiet, dense. Near-black terminal background, slightly lighter chrome for sidebars and bars, hairline borders, no heavy shadows or gradients.
- Spaces have small rounded monogram tiles in muted colors (W teal, C orange, P blue, E green, S purple) with a branch name on the right.
- Spaces are grouped by machine ("This computer", "macbook", "vps") with a small machine icon.
- Agent rows: the agent's program icon, the tab name, an age ("<1m", "4m"), and a status at the right edge: green dot = done, small spinner ring = working, hollow dot = idle, amber **"Needs you"** pill = blocked.
- Terminal text is monospaced; UI text is SF Pro, small (11–13 pt) like the desktop. Diff lines use dark red / dark green row backgrounds.
- A dark theme only, for now.

## Screens to design

1. **iPad, landscape — main view.** Essentially the desktop screenshot adapted to iPadOS: a left sidebar with *Spaces* (grouped by machine) on top and *Agents* (grouped by space) below, Settings at the bottom; a tab bar across the top (each tab shows its agent icon and status); the terminal fills the rest. Show one tab split into two terminal panes side by side.

2. **iPhone — terminal of a waiting agent (the hero screen).** The agent's terminal (Claude Code asking for permission to run a command, with options 1/2/3). Header: back/drawer button, agent icon + tab name, space + machine as a subtitle, status pill. At the bottom, above the keyboard: a **reply field** (multi-line, with a send button and a mic for dictation) and a compact **key bar**: Esc, Tab, ↑ ↓ ← →, ^C, ⏎, and quick 1 / 2 / 3 buttons for permission prompts. The keyboard is open.

3. **iPhone — drawer open.** The same sidebar as the iPad (Spaces by machine, Agents by space) slides in from the left over the dimmed terminal. Agents that need the user sort to the top, with a count badge on the drawer button.

4. **iPhone — tab with a split.** A small segmented switcher under the header picks which pane of the split is shown.

5. **iPhone — the lock-screen notification** that leads to screen 2 (it is delivered by the ntfy app, so only design the content): title "Claude Code · website", body "Do you want me to delete the old migrations and recre…".

6. **Onboarding flow (iPhone), one screen per step:**
   1. Welcome — what the app does and what it needs (a Mac running Herdr, Tailscale on both devices).
   2. Pick your Mac — a list of the user's Tailscale devices (name, OS icon, online dot; online Macs on top), loaded after they paste a Tailscale API key once (with a short "why" line and a Skip link). Below it, "Enter manually": host (MagicDNS name or 100.x IP) and user.
   3. SSH key — a generated public key, a one-line copyable command to add it to `~/.ssh/authorized_keys`, a hint to turn on Remote Login on the Mac, an "Import existing key" link, and a "Check" button.
   4. Trust this Mac — the host key fingerprint and a "Trust" button.
   5. Checking Herdr — a short checklist that ticks off: reachable, signed in, Herdr found. If Herdr isn't found, a field for its path.
   6. Done — "Found 5 spaces and 7 agents on mac-studio", then into the app.
   7. Notifications (skippable) — install the ntfy app, subscribe via a link/QR, run one command on the Mac, and a "Send test notification" button.
   Every step shows specific errors in plain words ("Tailscale is off on this phone", "Your Mac didn't accept the key") with Retry — never a generic "Connection failed". Show the device-list step and one error state.

7. **Connection states.** (a) A slim reconnecting banner shown when the app returns to the foreground. (b) The Mac is unreachable (Tailscale off / Mac asleep), with a Retry button.

8. **Unsupported panel.** A tab pane that holds a desktop *mod* the phone can't draw: a calm card saying "This panel is a desktop mod (`changes`). It isn't supported on iPhone yet." Don't make it look like an error.

## Constraints

- Respect iOS safe areas, Dynamic Type for UI text (not for the terminal grid), and 44 pt minimum touch targets in the key bar and reply field.
- The reply field and key bar must never cover the last line of the terminal.
- Don't invent features: no chat bubbles, no AI summaries, no social elements. It is a terminal client with an agent inbox.
- Use realistic content from the screenshot (spaces website/core/plugins/extensions/service-api; tabs pricing page, og tags, blog pass, docs nav).
