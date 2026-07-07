# Changelog

## Unreleased

## 0.1.5 - 2026-07-07

- Fixed desktop widget resizing by preserving the current window frame during refreshes.
- Increased the default widget height for a longer graph area.
- Added resize behavior to the right edge, bottom edge, and bottom-right handle.

## 0.1.4 - 2026-07-07

- Added an optional menu bar energy-flow field with colored up/down arrows for solar, battery, and grid flow.
- Colored energy-flow values from green through yellow to red depending on storage/export versus consumption/import.
- Improved graph time axes so 24h, 7-day, 30-day, and custom ranges show matching x-axis ticks.
- Added a visible resize handle and stronger size persistence to the floating desktop widget.
- Updated the GitHub homepage screenshots and feature text for the new flow and graph behavior.

## 0.1.3 - 2026-07-07

- Hid unused command or URL fields in the data source settings depending on the selected mode.
- Made the desktop widget resizable.
- Added minimum sizing to the detached graph window for safer resizing.

## 0.1.2 - 2026-07-07

- Added graph controls to show or hide battery, solar, and grid import lines.
- Added the same graph controls to the detached large graph window.
- Added optional colored energy-flow arrows for the menu bar.
- Cleared stale demo values when switching to an unconfigured live data source.
- Strengthened metric panel background colors while keeping each metric's color identity.
- Changed grid import icon color to blue/teal for clearer distinction.

## 0.1.1 - 2026-07-07

- Added clearer screenshots to the GitHub homepage and README.
- Improved tooltip texts with short explanations for each field.
- Reworded metric tooltips so they explain what each field means.
- Added total yield as a dashboard, widget, and menu bar metric.
- Lightened metric panel backgrounds and made panel animation more subtle.
- Raised graph power scale to at least 2000 W.
- Added subtle graph line animation.
- Added soft animated backgrounds to dashboard and widget metric panels.

## 0.1.0 - 2026-07-07

Initial local release of SolixBar.

- Native macOS menu bar app for Anker SOLIX overview data.
- Demo mode, local JSON command mode, and JSON URL mode.
- Configurable menu bar metrics, labels, symbols, icon visibility, and scaling.
- Login autostart support.
- Modern dropdown dashboard with battery, solar, home consumption, grid import, battery flow, daily yield, and status.
- History graph with battery, solar, and grid import lines.
- Time ranges: current, 24 hours, 7 days, 30 days, and custom.
- Enlarged graph window.
- Floating desktop widget window.
- Short tooltips for settings, metric cards, graph controls, and widget fields.
- App icon and packaged macOS app bundle script.
