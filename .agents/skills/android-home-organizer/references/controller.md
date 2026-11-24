# Controller runbook

## Requirements and scope

Use an already authorized ADB shell with read/write access to `/dev/uhid`, Python 3,
and an Android-native C compiler. In Termux, the relevant packages are
`android-tools`, `python`, and `clang`. A desktop build requires an Android NDK
compiler targeting the connected device ABI; a desktop Linux binary will not work.
Do not install dependencies unless installation is within the user's task scope.

This mechanism was exercised on a non-rooted HyperOS device with Android 16.
Compatibility with other devices is unverified. OEM security-setting prompts can
remain unchanged. UHID access itself is not guaranteed.

## Build and probe

Run from the skill directory. Keep generated binaries and private observations
outside the repository. Set `ANDROID_SERIAL` from the intended current ADB device,
and set the observed screen width and height without saving them in source files.

```bash
build_dir=$(mktemp -d)
clang -std=c11 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror -O2 \
  scripts/uhid-control.c -o "$build_dir/control"
python3 scripts/control.py --serial "$ANDROID_SERIAL" \
  --binary "$build_dir/control" --width "$SCREEN_WIDTH" --height "$SCREEN_HEIGHT" --probe
```

The probe briefly registers a virtual touchscreen and keyboard and removes them.
It sends no input. It checks Android input-reader classification and the active
internal display's natural orientation. It does not toggle permissions or install
an Android package. Do not start concurrent controller sessions on one device.

The HID descriptor includes contact ID and contact count. Omitting them can make
Android classify absolute coordinates as a pointer/touchpad instead of a direct
touchscreen. The kernel accepting a device or a report is not sufficient evidence
that a gesture affected the UI.

## Interactive operation

Start the same command without `--probe` and keep stdin open in a tool session.
Send one JSON object per line; each successful command prints `ok`. Close stdin
when finished. There is no network listener or persistent Android service.

Examples below are schematic coordinates, not a layout to replay. Replace every
coordinate using the current screen, and inspect state between dependent actions.

```json
{"op":"tap","x":100,"y":200}
{"op":"swipe","x":500,"y":700,"to_x":100,"to_y":700}
{"op":"drag","x":100,"y":200,"to_x":300,"to_y":500,"hold":0.85,"settle":0.8}
{"op":"text","value":"Tools","package":"com.miui.home","resource":"com.miui.home:id/title","select_all":true}
```

- `hold` is the delay before movement; `settle` is the delay over the destination.
  A same-point drag provides a long press. Timings are bounded to five seconds.
- The text target must be an enabled, focused, non-password `EditText`. No text is
  emitted if it is missing. Package and resource ID must come from the live dump.
- Text accepts basic Latin letters, digits, and spaces only, using HID key usages.
  Other writing systems remain supported through the Android on-screen keyboard,
  not through this helper's text encoder. Never silently transliterate folder names.
- No Enter is emitted. Confirm/save with a control verified in the current UI.
- Stop the session on a changed display, connection loss, or unexpected UI. The
  helper validates dimensions but does not identify every tap target on your behalf.

To check a JSON action without ADB, pass `--dry-run --width ... --height ...` and
pipe the action to stdin. Dry-run verifies syntax, bounds, and supported text only;
focus and device compatibility require live inspection.

## Observation and cleanup

Bring the launcher forward without key injection:

```bash
adb -s "$ANDROID_SERIAL" shell am start \
  -a android.intent.action.MAIN -c android.intent.category.HOME
```
This may restore an open folder; verify the workspace before the next tap.

Capture screenshots with `adb exec-out screencap -p` and XML with `uiautomator dump`
using explicitly selected devices and temporary paths. Avoid scanning other apps
or collecting unrelated account data.

The controller uses a uniquely named directory under `/data/local/tmp`, removes it
on normal exit/error, and destroys its UHID device on EOF. After connection loss,
cleanup may fail and must be verified when reconnected. Remove the local build
directory when it is no longer needed.

## Primary references

- [Android HID command protocol](https://android.googlesource.com/platform/frameworks/base/+/master/cmds/hid/README.md)
- [Linux UHID interface](https://docs.kernel.org/hid/uhid.html)
- [scrcpy input modes](https://github.com/Genymobile/scrcpy/blob/master/doc/mouse.md)

These describe input mechanisms, not a guarantee that a particular launcher or OEM
permits them. Prefer observations from the current authorized device.
