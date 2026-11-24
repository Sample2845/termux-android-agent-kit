---
name: android-home-organizer
description: Organize Android launcher icons and folders through an authorized ADB connection, using a temporary UHID touchscreen when normal input commands are unavailable. Use for home-screen arrangement and folder naming, not app installation or device unlocking.
---

# Android Home Organizer

Arrange the user's launcher through visible UI interactions. Preserve widgets, apps,
and shortcuts unless the request includes changing them. Choose categories from the
observed apps and the user's preferences; do not reuse another device's layout.

## Establish control

1. Check `adb devices -l` and select the intended device explicitly with `-s`.
   Never embed connection details in a script. Obtain current connection details
   from the user if the existing paired connection is unavailable.
2. Read the visible UI with `uiautomator dump` and a screenshot. Store these outside
   the repository: they can contain account information and private notes.
3. Prefer available standard input. If `adb shell input` reports missing
   `INJECT_EVENTS`, distinguish normal debugging from the OEM's additional security
   setting. Some OEM flows require a SIM; do not assume that every debugging
   setting has the same requirement or that the user can enable it.
4. A temporary UHID device is an alternative input path **only if the already
   authorized shell can access `/dev/uhid`**. It does not grant `INJECT_EVENTS`,
   enable restricted settings, install an APK, or require root. Read
   [the controller runbook](references/controller.md) to compile and probe it.
   Stop this route if access is denied; do not change device-node permissions,
   security policies, or framework settings to force access.
5. The bundled controller supports a single active internal display in its natural
   orientation. Check dimensions against a fresh screenshot. A successful probe
   proves registration and classification, not that gestures will work on every ROM.
   Verify a reversible swipe before moving any icon.

## Inspect, arrange, verify

- Record each page's icons, folders, widgets, and dock before editing. UI dumps and
  screenshots are visual records, not a restorable launcher database backup.
- Explain the proposed grouping briefly, then perform the authorized arrangement.
  Preserve any categories or placements the user explicitly requested.
- Long-pressing may shrink and reposition the entire launcher grid. The drag source
  uses normal-screen coordinates; the target must use the observed edit-mode grid.
  Inspect a held drag or edit-mode screenshot instead of assuming an offset.
- Create a folder by dropping one app onto another and waiting for the folder
  preview. Check the result before adding more apps. Batch only movements whose
  source and destination positions are still known.
- To transfer an icon between pages, hold near the observed edge, wait for the
  transition, then inspect the landing position. A launcher may remove empty pages.
- Rename only after confirming an enabled, focused `EditText` in the launcher.
  On some launchers the folder title first requires a long-press to enter edit
  mode, followed by a tap. A visible title is not necessarily editable.
- The helper's `text` action requires the expected package and resource ID, rejects
  unsupported characters before typing, and never sends Enter. It uses basic HID
  key usages, so the active physical-keyboard layout must match the intended text.
  Use the on-screen keyboard for other scripts or characters; choose names in the
  user's language. Read back the result before saving with a visible UI control.
- Escape is **not** a reliable Android Back action. Close a folder by tapping a
  verified blank area outside it and confirm that the launcher workspace returned
  before touching the next folder. Otherwise the next tap can open an app.
- Verify every moved app in its intended folder, page count, dock, and final visual
  arrangement. On unexpected navigation, stop typing and regain the launcher.
  Do not interact with an accidentally opened app's account or transaction flows.

## Finish

Close the controller's stdin or interrupt it to remove the virtual device and
remote temporary files. Confirm that `Home Organizer Control` is absent from
`adb shell getevent -lp`. If ADB disconnected during cleanup, reconnect and inspect
remaining processes and temporary files before claiming cleanup succeeded.

Report the arrangement, verification, any unfinished work, and unexpected side
effects. Do not publish screenshots, UI dumps, app inventories, connection details,
or transcripts with reusable code.
