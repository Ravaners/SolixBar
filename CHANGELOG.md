# Changelog

## Unreleased

## 0.3.7 - 2026-07-10

- Fixed automatic refresh scheduling by running the macOS refresh timer in common run loop modes, so updates continue reliably while menus or UI tracking are active.

## 0.3.6 - 2026-07-10

- Restored high-contrast bright text in the detached slim bar with a darker glass surface and text shadow.
- Hid `Gesamt`/total yield automatically when the SOLIX data source cannot provide a real cumulative total.

## 0.3.5 - 2026-07-09

- Corrected total-yield handling so a newly entered Anker app cumulative value resets the local runtime counter instead of leaving `Gesamt` at today's value.
- Ignored zero-valued API totals when choosing a total-yield source and added an extra SOLIX statistics lookup.
- `Gesamt` now stays empty instead of showing the local daily/runtime counter when neither the API nor the configured Anker app start value provides a true cumulative total.
- Improved readability of default text in the detached slim bar on bright/glass backgrounds.
- Rounded the app icon shown in the menu bar and detached slim bar.

## 0.3.4 - 2026-07-09

- Replaced the app icon with the approved brighter modern SolixBar icon.
- Updated the bundled macOS `.icns`, in-app PNG icon, and project homepage icon.

## 0.3.3 - 2026-07-09

- Added a one-time menu bar migration so Netzbezug/grid import appears in the selected menu bar values.
- Improved menu bar text contrast, especially for PV values on light menu bars.
- Fixed compact history graph spacing so labels, axes, and lines no longer overlap.
- Centered custom day input values horizontally and vertically in dashboard and detached history windows.
- Added more detailed log entries for user actions, graph changes, detached views, settings preview/save/reset, and manual refresh.

## 0.3.2 - 2026-07-09

- Added a local Gesamtertrag/total-yield start value for SOLIX live mode when Anker does not expose the cumulative app value through the API.
- SolixBar now continues counting total yield from the entered Anker app value instead of showing only the local runtime counter.

## 0.3.1 - 2026-07-09

- Renamed the home metric from Haus/Hausverbrauch to Hauslast.
- Corrected Solarbank 4 home-load mapping to prefer real smart-meter home load over Solarbank output power.
- Corrected grid mapping so export is shown as a negative grid value instead of zero.
- Added an optional local correction field for today's yield when Anker reports 0 kWh for the day.
- Reduced tooltip delay for help question marks to about 0.1 seconds.

## 0.3.0 - 2026-07-09

- Removed the desktop widget from the app and project homepage.
- Added visible question-mark help controls next to settings, with short explanations on hover.
- Added a setting to lock or unlock the detached slim menu bar so it cannot be moved accidentally.
- Added app appearance settings for automatic system mode, light mode, and dark mode.
- Added an app language setting for German or English visible UI text.
- Changed the detached slim menu bar menu action so it switches between detach and dock.
- Forced the app icon to appear in the macOS menu bar while the slim bar is detached, even when the icon is normally hidden.

## 0.2.0 - 2026-07-09

- Updated the project homepage with a new rendered screenshot of the detached slim menu bar.
- Bumped the app to the 0.2 series after the larger detached-bar, widget-resize, graph, logging, and homepage updates.

## 0.1.22 - 2026-07-09

- Moved the detached slim menu bar to desktop-accessory level so normal app windows always appear in front of it.

## 0.1.21 - 2026-07-09

- Added fullscreen-space detection for the detached slim menu bar: it remains available on normal desktops but hides automatically on fullscreen app spaces.
- Restored the detached slim menu bar automatically when returning from a fullscreen space to a normal desktop.

## 0.1.20 - 2026-07-09

- Kept the detached slim menu bar at normal window level while making it visible on all macOS desktops again.

## 0.1.19 - 2026-07-09

- Changed the detached slim menu bar from a floating panel to a normal borderless window so other windows can move in front of it.
- Removed the always-on-top behavior from the detached slim bar while keeping its saved position and custom appearance.

## 0.1.18 - 2026-07-09

- Added reliable edge-drag resizing to the desktop widget so width and height can be changed directly at the window border.
- Improved the history graph with a modern gradient background, clearer plot area, stronger line colors, soft line shadows, and subtle area fills.
- Saved the detached slim menu-bar position and restored it after app restart.
- Changed the detached slim bar behavior so it no longer stays above fullscreen apps.

## 0.1.17 - 2026-07-09

- Added a local app log file at `~/Library/Application Support/SolixBar/SolixBar.log` plus a menu action to reveal it.
- Restored the detached slim menu bar automatically after app restart when it was active before quitting.
- Refined the detached slim bar with a more colorful but readable accent gradient based on the selected metrics.
- Strengthened energy-flow colors for solar production, battery storage, and consumption.

## 0.1.16 - 2026-07-09

- Improved the detached slim bar background with a more readable modern macOS-style surface.
- Removed the duplicated Online/Offline label from the detached slim bar.
- The macOS menu bar now shows Online/Offline with a colored status dot while the slim bar is detached.
- Added a separate scaling control for the detached slim bar.

## 0.1.15 - 2026-07-09

- Fixed the detachable slim menu-bar window so it uses the same symbols, arrows, colors, order, and selected values as the real macOS menu bar.
- The detached slim bar now resizes automatically based on the number of visible values.
- While the slim bar is detached, the macOS menu bar keeps only an Online/Offline status label and restores the full value display when the slim bar is closed.
- Added a glass-style background to the detached slim bar.

## 0.1.14 - 2026-07-09

- Added a detachable slim menu-bar window that mirrors the selected menu-bar values below the macOS menu bar.
- The detached slim bar stays independent from the large dashboard and can be closed with its inline close button.
- While the slim bar is detached, the full value text is removed from the macOS menu bar and restored when the slim bar is closed.

## 0.1.13 - 2026-07-09

- Added visible app version information in the settings window and menu.
- Added a detachable dashboard window that opens below the macOS menu bar.
- Removed the custom desktop-widget resize overlay so macOS native window resizing can work without intercepted mouse events.
- Fixed Solarbank 4 battery-flow mapping by using the signed charging power field.
- Added local fallback energy counting for today's and total solar yield when the Anker API reports `0.00`.
- Improved menu bar energy-flow arrows with higher-contrast green/red glyphs instead of low-contrast yellow arrows.
- Reduced overlap risk in compact history graph layouts.

## 0.1.12 - 2026-07-07

- Removed all desktop-widget scale buttons and the widget-size slider.
- Simplified desktop-widget resizing so the window is resized by dragging the edge or corner.
- Updated the project site to use rendered PNG screenshots, including a new desktop-widget image.

## 0.1.11 - 2026-07-07

- Fixed data-source settings so Demo, local JSON command, and JSON URL can be selected again without SOLIX login fields forcing the local helper mode.
- Data-source settings now only show the fields relevant to the selected mode.
- Improved desktop widget resizing with native resize support, wider visible resize handles, and a direct widget-size slider.
- Kept today energy visible by falling back to `0.00 kWh` while Anker has not yet reported a daily energy total.
- Updated the GitHub Pages site to describe the corrected live setup and widget behavior.

## 0.1.10 - 2026-07-07

- Fixed live SOLIX mapping for Solarbank 4 systems so the app receives real battery, solar, home load, grid, and battery-flow values instead of empty `null` fields.
- Added a guarded today-energy lookup for the live SOLIX helper.

## 0.1.9 - 2026-07-07

- Added SOLIX login fields for email, password, and country directly to the data source settings.
- Saving SOLIX login fields now writes the local ignored `work/solixbar.env` file automatically.
- Saving SOLIX login fields also switches the app to the prepared local JSON helper command.

## 0.1.8 - 2026-07-07

- Added explicit plus and minus controls inside the desktop widget for reliable scaling.
- Clarified the energy-flow settings: the energy-flow field is separate from the option that shows colored direction arrows.
- Moved graph legend labels below the title to avoid overlap with the selected time range.
- Increased x-axis tick density for 24-hour, 7-day, 30-day, and custom graph ranges.

## 0.1.7 - 2026-07-07

- Replaced the app icon with the new energy-flow battery design.
- Switched menu bar energy-flow indicators to clear text arrows that change direction by import, export, charging, and discharging.
- Added visible right, bottom, and corner resize grips to the desktop widget.
- Added colored label backgrounds to the graph legend.

## 0.1.6 - 2026-07-07

- Made graph x-axis labels explicitly depend on the selected range.
- 24-hour ranges now show time labels, while 7-day and longer ranges show date-based labels.
- Kept grid and x-axis labels visible even when there are not yet enough samples for a line.

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
