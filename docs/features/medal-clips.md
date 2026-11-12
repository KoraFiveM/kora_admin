---
title: Medal clips
sidebar_position: 5
---

# Medal clips

The Developer Tools, Medal Clips tab saves a highlight from the local [Medal](https://medal.tv) recorder of the admin who clicks the button. Medal's Auto-Clipping API listens only on the player's own `localhost`, so `client/medal.lua` sends the request through kora_admin's invisible NUI page (`web/medal.html`, `web/medal.js`) to `http://localhost:12665/api/v1/event/invoke`. Nothing goes through the server.

## Setup

1. Generate a public key and register your event IDs with [Medal's Auto-Clipping builder](https://medal.tv/developer/auto-clipping).
2. Add the key as a replicated convar (preferred, so resource updates do not overwrite it):

   ```cfg
   setr kora_admin_medal_public_key "your-public-key"
   ```

   Alternatively set `Config.medal.publicKey`. A non-empty convar named by `Config.medal.publicKeyConvar` wins.
3. Configure one entry per clip button in `Config.medal.events`. IDs, names, durations and capture delays must match what you registered with Medal:

   ```lua
   events = {
       { id = '1', name = 'Admin Clip', duration = 30, captureDelayMs = 0 },
   },
   ```

4. Medal must be installed and running on each admin's PC.

## Behaviour

- The tab is visible to `Config.medal.menuLevel` (default `admin`). Buttons are labelled with the event name and duration, for example "Save Admin Clip (30s)", and are disabled until a public key and at least one event are configured.
- Each click sends `eventId`, `eventName`, `triggerActions = { 'SaveClip' }` and `clipOptions` (duration, capture delay). An event with a non-numeric id, empty name, non-positive duration or negative delay is refused locally.
- Results: HTTP 200 shows "Medal accepted ...". The clip is then processed asynchronously by the Medal app. 401 reports a rejected public key, 400 a rejected event, anything else (or no answer within `Config.medal.requestTimeoutMs`, default 5000 ms, clamped to 1-30 s in the browser) reports that Medal could not be reached.
