[日本語](lang/ja/README.md)

# AgentPad

Drive your macOS AI coding agents (Claude Code, Cursor, Codex, …) from a game controller. Keep your hands on the pad — approve, reject, scroll diffs, switch hunks, send chat — without breaking flow.

Built on top of a Joy-Con / Pro Controller / Famicom / SNES Controller key mapper for macOS.

![screenshot](resources/screenshot/screenshot_1.png)

## Why AgentPad

Agentic coding sessions are a stream of small yes/no decisions: approve a tool call, reject a diff, run the next step. Keyboard shortcuts work, but they pull your hands away from reading. AgentPad turns a game controller into a dedicated **agent remote**:

- **Approve / reject with thumbs only** — map A / B to `y` / `n`, or to whatever shortcut your agent uses.
- **Per-app profiles** — one mapping for Claude Code in Terminal, another for Cursor, another for your browser — switched automatically by the frontmost app.
- **Passthrough per app (PS / Xbox / MFi)** — for DualShock 4 / DualSense / Xbox / MFi controllers, the per-app passthrough setting hands the device back to the system so the foreground app sees a native gamepad.

### Example: Claude Code in Terminal

| Button | Action |
| --- | --- |
| A | `y` (approve) |
| B | `n` (reject) |
| L / R | scroll up / down |
| Start | `Ctrl+C` |
| Home | focus terminal / switch profile |

## Features

- Map controller buttons / sticks to keyboard keys, mouse buttons, or system actions.
- **Per-app key mappings** — switch profiles automatically based on the frontmost app.
- **Simple capture mode** — press any keyboard key once and it is assigned immediately (no modifier checkboxes, no dropdown). Detailed mode is still available for combo keys.
- **Sync from Default** — overwrite a per-app mapping with the default profile in one click (with Undo support).
- **Passthrough per app (PS / Xbox / MFi only)** — for non-Nintendo controllers, mark an app as Passthrough so the controller behaves as a native gamepad in that app. See [Known Limitations](#known-limitations) for why this does not work for Joy-Con / Pro Controller.
- **Controller list shows the model name** (Joy-Con (L) / Joy-Con (R) / Pro Controller / SNES / Famicom 1 / Famicom 2) under each icon.
- **Accessibility permission walkthrough** — guides you through granting the required system permission on first launch.
- Native AppKit UI that follows the system appearance (Light / Dark Mode).

Supported controllers today: Joy-Con (L), Joy-Con (R), Pro Controller, Famicom Controller 1 / 2, SNES Online Controller. DualShock 4 / DualSense / Xbox / MFi support is on the roadmap — see [docs/plan.md](docs/plan.md).

## Install from GitHub

1. Download `AgentPad-vX.X.X.dmg` from [Releases](<TODO: repo-url>/releases).
2. Copy `AgentPad.app` to `/Applications`.

![screenshot_install](resources/screenshot/screenshot_2.png)

## How to use

1. Connect your controller via Bluetooth

    1.1. Open "System Settings" > "Bluetooth" on your Mac

    1.2. Hold down your controller's sync button

    1.3. Click the "Connect" button

    ![screenshot_usage_1_3](resources/screenshot/screenshot_3.png)

2. Set key mappings

    2.1 Launch AgentPad.app

    2.2 Choose the "Settings…" menu

    ![screenshot_usage_2_2](resources/screenshot/screenshot_4.png)

    2.3 Add apps to set per-app key mappings (optional). Use **Sync from Default** to copy the default mapping to the selected app, or toggle the **Passthrough** checkbox to leave the controller untouched for that app.

    ![screenshot_usage_2_3](resources/screenshot/screenshot_5.png)

    2.4 Click a button to set a key. The capture dialog supports two modes:

    - **Simple** — press any keyboard key once; it is assigned and the dialog closes.
    - **Detailed** — pick a key plus ⌘ / ⌥ / ⌃ / ⇧ modifiers, or a mouse button.

    ![screenshot_usage_2_4_1](resources/screenshot/screenshot_6.png)

    ![screenshot_usage_2_4_2](resources/screenshot/screenshot_7.png)

3. Allow AgentPad to control Accessibility

    3.1 When you start using your controller, the in-app onboarding (or a system alert) will appear.

    ![screenshot_usage_3_1](resources/screenshot/screenshot_8.png)

    3.2 Open "System Settings" > "Privacy & Security" > "Accessibility", and enable "AgentPad.app".

    ![screenshot_usage_3_2](resources/screenshot/screenshot_9.png)

## Known Limitations

### Nintendo controllers cannot be used in games while AgentPad is running

AgentPad uses the IOKit HID API in **exclusive seize** mode to read Joy-Con and Pro Controller — that is the only path on macOS that exposes the rumble, IMU, player LEDs and full button set for these devices. As long as AgentPad has them seized, **no other process — including Switch emulators, Steam, or any game — can read input from them**.

The Passthrough setting and quitting AgentPad both close the IOKit handle, but macOS does not re-publish a Bluetooth Nintendo controller to other clients after a seized session ends. **To use a Joy-Con / Pro Controller in a game, disconnect the controller from the Mac's Bluetooth menu (or power-cycle the controller) and reconnect it after quitting AgentPad.**

This limitation only applies to Nintendo controllers. **PlayStation, Xbox, and MFi controllers go through `GameController.framework`**, which is a shared system path — Passthrough per app works normally for them.

## Roadmap

- DualShock 4 / DualSense / Xbox / MFi controllers via `GameController.framework`.
- Sparkle 2 auto-updates for the GitHub build.

See [docs/plan.md](docs/plan.md) for the full plan.

## Build from source

Requires Xcode and CocoaPods.

```sh
pod install
open AgentPad.xcworkspace
```

Build & run the `AgentPad` scheme.

## See also

[JoyConSwift](https://github.com/magicien/JoyConSwift) — IOKit wrapper for Nintendo Joy-Con and Pro Controller (macOS, Swift), used by AgentPad's Joy-Con backend.
