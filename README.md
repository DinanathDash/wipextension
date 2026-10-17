# Wipextension

Wipextension is a droplet for [Droppy](https://getdroppy.app) that safely locks your keyboard, dims your built-in screen, and blocks built-in trackpad input so you can clean your Mac without unintended keystrokes or clicks.

## Features

- **Multi-Mode Cleaning:** Clean your keyboard, display, or both.
- **Built-in Screen Dimming:** Automatically dims the built-in display to 0% brightness so dust and smudges are easy to wipe, and restores your previous brightness level when done.
- **Trackpad Lock Option:** Blocks built-in trackpad input while keeping external USB and Bluetooth mice active.
- **Minute Tape Timer:** High-precision 1–30 minute scrollable tick tape scrubber to set your cleaning duration.
- **Safety Net:** Automatically unlocks when your Mac goes to sleep or the screen locks.
- **Live Activity Integration:** Visual confirmation in the Dynamic Island while cleaning is active.

## Usage

1. Open Droppy and add the Wipextension widget to your shelf.
2. Select your cleaning mode (Keyboard, Display, or Both) and scroll to set your desired cleaning duration (1–30 mins).
3. Click **Start Cleaning** or use your configured global shortcut to begin cleaning.
4. Clean your Mac!
5. Click **Stop Cleaning**, press your unlock shortcut, or wait for the countdown to unlock.

## Developing

```bash
droppykit run        # open it in Droppy's Settings panel
droppykit build      # produce Wipextension.droplet
droppykit validate   # the checks a submission runs
droppykit submit     # open the submission form, filled in from this checkout
```

## The surfaces

| Surface | Protocol |
| --- | --- |
| Shelf widget | `ShelfWidgetProviding` |
| Live activity, compact and expanded | `LiveActivityProviding` |
| Settings pane | `SettingsPaneProviding` |

## Repository layout

```
Sources/Wipextension/           the droplet's code
Wipextension.icon/              the app icon artwork
Assets/                         bundled assets (like Creator.png)
droplet.json                    the manifest
```

## Credits & Acknowledgements

- **High Alert by Jordy Spruit:** The minute tape scrubber and velocity energy model adapt the design language and mechanics of Droppy's High Alert timer, provided by Jordy Spruit with permission. Learn more at [Droppy](https://getdroppy.app).
- See [ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md) for full attribution.

## Licence

MIT. See [LICENSE](LICENSE).
