[日本語](https://github.com/magicien/ControllerKeyMapper/blob/master/lang/ja/README.md)

# AgentPad
Nintendo Joy-Con / Pro Controller / Famicom Controller / SNES Controller key mapper for macOS — built to drive AI agents.

![screenshot](https://github.com/magicien/ControllerKeyMapper/blob/master/resources/screenshot/screenshot_1.png)

## Features

- Map controller buttons / sticks to keyboard keys, mouse buttons, or system actions.
- Per-app key mappings: switch profiles automatically based on the frontmost app.
- **Simple capture mode** — press any keyboard key once and it is assigned immediately (no modifier checkboxes, no dropdown). Detailed mode is still available for combo keys.
- **Sync from Default** — overwrite a per-app mapping with the default profile in one click (with Undo support).
- **Passthrough per app** — keep the controller as a native game controller for selected apps instead of remapping it.
- **Controller list shows the model name** (Joy-Con (L) / Joy-Con (R) / Pro Controller / SNES / Famicom 1 / Famicom 2) under each icon.
- Supported controllers: Joy-Con (L), Joy-Con (R), Pro Controller, Famicom Controller 1 / 2, SNES Controller.
- Native AppKit UI that follows the system appearance (Light / Dark Mode).

## Install from App Store (Recommended)

[Mac App Store page](https://apps.apple.com/app/joykeymapper/id1511416593)

## Install from Github

1. Download a dmg file (AgentPad-vX.X.X.dmg) from [Releases](https://github.com/magicien/ControllerKeyMapper/releases)

2. Copy AgentPad.app to Applications
![screenshot_install](https://github.com/magicien/ControllerKeyMapper/blob/master/resources/screenshot/screenshot_2.png)

## How to use

1. Connect your controller via Bluetooth

    1.1. Open "System Preferences" > "Bluetooth" on your Mac

    1.2. Hold down your controller's sync button

    1.3. Click the "Connect" button

    ![screenshot_usage_1_3](https://github.com/magicien/ControllerKeyMapper/blob/master/resources/screenshot/screenshot_3.png)

2. Set key mappings

    2.1 Launch AgentPad.app

    2.2 Choose the "Settings..." menu

    ![screenshot_usage_2_2](https://github.com/magicien/ControllerKeyMapper/blob/master/resources/screenshot/screenshot_4.png)

    2.3 Add apps to set per-app key mappings (optional). Use **Sync from Default** to copy the default mapping to the selected app, or toggle the **Passthrough** checkbox to leave the controller untouched for that app.

    ![screenshot_usage_2_3](https://github.com/magicien/ControllerKeyMapper/blob/master/resources/screenshot/screenshot_5.png)

    2.4 Click a button to set a key. The capture dialog supports two modes:

    - **Simple** — press any keyboard key once; it is assigned and the dialog closes.
    - **Detailed** — pick a key plus ⌘ / ⌥ / ⌃ / ⇧ modifiers, or a mouse button, the same as before.

    ![screenshot_usage_2_4_1](https://github.com/magicien/ControllerKeyMapper/blob/master/resources/screenshot/screenshot_6.png)

    ![screenshot_usage_2_4_2](https://github.com/magicien/ControllerKeyMapper/blob/master/resources/screenshot/screenshot_7.png)

3. Allow AgentPad to control Accessibility

    3.1 When you start using your controller, you will see this alert.

    ![screenshot_usage_3_1](https://github.com/magicien/ControllerKeyMapper/blob/master/resources/screenshot/screenshot_8.png)

    3.2 Open "System Preferences" > "Security & Privacy" > "Privacy" tab > "Accessibility", and check "AgentPad.app"

    ![screenshot_usage_3_2](https://github.com/magicien/ControllerKeyMapper/blob/master/resources/screenshot/screenshot_9.png)

## Build from source

Requires Xcode and CocoaPods.

```sh
pod install
open AgentPad.xcworkspace
```

Build & run the `AgentPad` scheme.

## See also

[JoyConSwift](https://github.com/magicien/JoyConSwift) - IOKit wrapper for Nintendo Joy-Con and ProController (macOS, Swift)
