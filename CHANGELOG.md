## [1.2.0] - 2026-11-17

- Upgraded DroppyKit dependency from 1.23.0 to 1.27.0.
- Added compact running HUD strip in the shelf widget with active mode display badge, circular stop control, and prominent 28pt semibold countdown timer.
- Dynamic shelf widget sizing (`ShelfWidgetDynamicLayoutProviding`) supporting slim 48pt HUD strip while cleaning and smooth transition back to the scrubber upon completion.
- Added smooth native unfold transitions (`DroppyTransition.compactContent`) between the idle scrubber shelf and running HUD.
- Modernized start and completion notifications using DroppyKit 1.25.0 Island Notification Pills (`DropletHUDCard`).
- Standardized shelf controls with native `DroppyWashPillButtonStyle` and `DroppyWashCircleButtonStyle`.
- Refined companion pill design with clean, full-size mode icon.
- Updated minute tape scrubber attribution to Jordy Spruit's Stay Awake design language.

---

## [1.1.0] - 2026-10-13

- Initial release of Wipextension (renamed from Clean Keyboard).
- Safely clean your Mac by locking the keyboard, dimming the built-in display, or both.
- Automatically dim the built-in screen brightness to 0% so smudges and dust are easy to wipe, and restore brightness when finished.
- Optional trackpad lock to block built-in trackpad gestures and clicks while keeping external USB and Bluetooth mice active.
- Precision 1–30 minute scrollable tick tape scrubber to dial in your cleaning duration with haptic feedback.
- Live numeric countdown and Dynamic Island live activity integration during cleaning sessions.
- Safety net automatically unlocks your Mac when it goes to sleep or the screen locks.
- Customizable global shortcut to quickly start and stop cleaning.

---

## [1.0.1] - 2026-09-23

- Automatically stop cleaning on system sleep or screen lock and update live activity UI.
- Update screenshots and report configurations for API 1.8.0.
- Update DroppyKit to 1.8.0 and refactor expanded view UI with transitions and delayed toggle.
- Add unlock confirmation state and handle event tap timeouts.
- Scope button to action area in widget and update DroppyKit to 1.7.1.
- Remove menu bar extra surface and associated settings.
- Redesign Live Activity UI components and layout.
- Add menu bar toggle setting, update droplet UI, and upgrade to DroppyKit 1.7.0.
- Upgrade DroppyKit to v1.6.3, add menu-bar-extra surface support, and add MIT license.

---

## [1.0.0] - 2026-09-20

- Initialize Clean Keyboard droplet project with package structure and configuration.
