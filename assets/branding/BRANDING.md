# Brand assets

## Mark

The mark is a focused app window with two semantic rails. The window represents bounded pixel capture. The rails represent UI Automation structure and accessible text.

The cyan corner signals explicit focus and capture without turning the mark into a generic camera icon.

The mark is deliberately distinct from the Windows logo and OpenAI branding.

## Palette

| Name | Value | Use |
|---|---:|---|
| Deep navy | `#0B1730` | App tile and repository artwork |
| Cobalt | `#155EEF` | Brand depth and focus |
| Cyan | `#42D4FF` | Semantic/focus accent |
| Ice | `#F4F8FF` | Marks on dark surfaces |
| Ink | `#10233D` | Marks on light surfaces |

## Theme behaviour

- The app icon and repository avatar use an opaque tile that works in either system theme.
- Use `on-light` tray assets when the system tray background is light.
- Use `on-dark` tray assets when the system tray background is dark.
- Swap assets when the Windows theme changes. Do not invert rendered pixels.
- README lockups have light and dark variants selected with a `<picture>` element and `prefers-color-scheme`.

## States

| State | Meaning |
|---|---|
| `idle` | Ready; no capture in progress |
| `capturing` | A user-requested capture is in progress |
| `success` | The most recent capture completed |
| `error` | The most recent capture failed |

State marks remain monochrome in the tray. Colour is not required to understand
them.

## Asset map

| Use | Asset |
|---|---|
| Windows executable, taskbar, Alt-Tab and shortcut | `windows/windows-appshots.ico` |
| Windows tray | `windows/tray-<state>-on-<theme>.ico` |
| App/plugin artwork | `app-icon-256.png` |
| Repository avatar | `repo/github-avatar-512.png` |
| GitHub social preview | `repo/github-social-preview-1280x640.png` |
| README header | `repo/readme-lockup-on-light.svg`, `repo/readme-lockup-on-dark.svg`, plus PNG previews |
| Editable source | `source/*.svg` |

## Usage rules

- Keep the full mark at or above 32 pixels.
- Use the optically simplified small mark below 32 pixels.
- Keep clear space around the mark equal to the width of one semantic node.
- Do not add a camera lens, Windows panes, mascot, text inside the icon, glow,
  drop shadow or extra detail.
- Do not use a tray icon as repository artwork or shrink the social-preview
  lockup into the tray.

These assets are original Windows AppShots project artwork and are distributed
under the repository's MIT licence.
