---
title: Player reports
sidebar_position: 3
---

# Player reports

Players file reports with a command; staff handle them in a queue with a live two-way chat. Reports, messages and read markers are stored in the database, so nothing is lost when kora_admin restarts. Commands and the admin menu call the same store (`server/reports.lua`), so validation, notifications and audit entries are identical.

## Submitting a report

```text
/report <type> <message>
/report bug The garage door at Legion Square does not open
```

- Types come from `Config.reports.types` (default `player`, `bug`, `exploit`, `gameplay`, `question`, `other`). The ids are stored with the report; labels may be renamed freely.
- The message is trimmed and cut to `Config.reports.maxMessageLength` (1000) characters.
- One connected player can open a new report every `Config.reports.cooldownSeconds` (30) seconds.
- Online staff (`Config.reports.staffLevel`, default `support`) get a notification "New Type report #id"; `exploit` reports use the error style.

## Statuses

| Status | Meaning |
| --- | --- |
| `open` | new or reopened, unassigned |
| `claimed` | a staff member is handling it (`claimed_by_name`) |
| `resolved` | closed with an optional resolution note |
| `dismissed` | closed with an optional reason |

Closed reports must be reopened before anyone can reply or claim them. Reopening clears the claim, resolution and close time. The reporter is notified of claims and status changes.

## Staff queue

Staff open the queue from the Reports workspace in `/admin`, or with `/reports [status] [type] [page]`, which opens a standalone "Player Reports" app with the same queue (set `Config.reports.command.ui = false` to print a chat list instead).

- Quick filters: Open, Claimed, Resolved, Dismissed, All, plus Filter Reports (status, type, reporter name or identifier, page).
- Columns: id, status, category, reporter, subject (first line, 60 characters), New (unread player messages since you last opened it, chat mode only), assigned staff member, age.
- The queue is sorted by status (open, claimed, resolved, dismissed) and then by last update; `Config.reports.pageSize` (20) rows per page.

Selecting a report opens three tabs:

- **Overview** - the report and conversation (live chat or a timeline), with Back to Report Queue.
- **Manage** - Claim / Take Over, Resolve (note required in the menu), Dismiss (reason required in the menu), or Reopen for closed reports. Without live chat this tab also has Reply to Reporter.
- **Online Reporter** - only when the reporter is online: Teleport to Reporter, Bring Reporter, Send Reporter Back, Spectate Reporter.

The reporter is located by citizen id or license among online players, never by the stored server id.

Typed equivalents: `/reportclaim <id>`, `/reportresolve <id> [note]`, `/reportdismiss <id> [note]`, `/reportreopen <id> [note]`, `/reportreply <id> <message>`, `/reportstatus <id>`.

### Live updates

While the queue or a report is open, kora_admin pushes `kora_admin:client:reportChanged` for new reports, replies, claims and status changes, and the open screen reloads in the background without losing the selected tab or a half-typed message. With `Config.reports.liveUpdates = false` only the staff member who made a change receives the push.

## Live report chat

With `Config.reports.chat.enabled = true` (default) every report has a two-way chat.

- **Staff** see the conversation as message bubbles with a message box on the report's Overview tab (Enter sends, Shift+Enter adds a line). It replaces Manage, Reply to Reporter.
- **Players** run `/reports` (or `/reports <id>`) to open **My Reports**: their own reports with an unread count and the same chat for each. With `chat.playerUi = false` players get the chat-list commands instead.
- New messages appear on both sides without reopening. If My Reports is closed when staff reply, the player gets a toast with a preview and a pointer to `/reports`.
- `chat.fixedLayout = true` makes the staff Overview and the player's report window fit the window; only the message list scrolls.

### Read and delivery ticks

Your own messages show:

- one tick, **sent** - saved, the other side has not received it;
- two grey ticks, **delivered** - it reached the other side's client (they were online, or their client has since loaded the report list);
- two accent ticks, **seen** - the other side opened the conversation.

For a player the original report counts as their first message. A player's message is seen once any staff member has opened the report; a staff message is seen once the reporter has. Staff-side delivery is tracked once per report under the `@staff` pseudo reader. Markers are stored in `admin_report_reads`.

### Validation

Every chat message goes through the `kora_admin:reportChatSend` callback and `Admin.replyToReport`, which checks that the sender owns the report (stored reporter license) or holds `staffLevel`, that the report is open, the length (`chat.maxLength`, refused rather than cut) and a per-sender sliding-window rate limit (`chat.rateLimit`, which also applies to `/reportreply` while chat is enabled). Text is stored as typed with control characters stripped and runs of blank lines collapsed, and is always rendered as text, never HTML. Chat output from `/reportstatus` and report lists replaces angle brackets with look-alike characters.

### Chat options

| Option | Effect |
| --- | --- |
| `chat.showStaffNames = false` | Players see "Staff" instead of staff names. |
| `chat.notifyStaff = 'claimer'` | Reporter messages notify only the claiming staff member (unclaimed reports still notify all staff). |
| `chat.enabled = false` | Restores the previous screens: a conversation timeline, Manage, Reply to Reporter, and chat lists for players. Messages are still stored in `admin_report_messages`. |

All options are listed in [Configuration](../configuration.md#reports).

## Chat-list mode

When no app is opened (`command.ui = false` for staff, chat or `playerUi` disabled for players, or the command runs from the console or Discord), `/reports` prints one line per report:

```text
#12 [open] Bug · PlayerName — The garage door at Legion Square does not … (5m)
```

Non-staff players only ever see their own reports and get a hint to use `/reportstatus <id>`.
