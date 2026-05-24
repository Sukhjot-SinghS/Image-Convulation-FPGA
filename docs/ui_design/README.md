# Handoff: FPGA Coprocessor UI — RISC-V Image Convolution Interface

## Overview
A desktop control interface for a RISC-V + FPGA image convolution accelerator. The user connects to hardware over UART, uploads a grayscale image, runs convolution on both the FPGA (hardware) and CPU (software), then compares timing/cycle performance side by side. Built as a replacement/upgrade to the existing `fpga_coprocessor_ui.py` (CustomTkinter).

## About the Design Files
The file `FPGA Coprocessor UI.html` is a **high-fidelity design prototype** built in React/HTML. It shows exact colours, layout, interactions, and animations. The task is to **recreate this design in the existing Python codebase** (`fpga_coprocessor_ui.py`) using CustomTkinter — or port it to a web frontend (Electron / Tauri / PyWebView) if desired. Do not ship the HTML file directly.

## Fidelity
**High-fidelity.** Pixel-accurate colours, typography, spacing, and interaction states. Recreate as closely as possible.

---

## Screens / Views

### Stage 1 — Connection Screen
Shown on first launch (or after disconnect). Occupies the full window.

**Layout:**
- Full-viewport dark radial gradient background (`#080C14` → `#0D1E35`)
- Subtle repeating horizontal scanline overlay (4px period, 25% opacity black)
- Corner accent brackets at all four corners (24px from edge, 24×24px, 2px stroke `#004466`)
- Vertically and horizontally centred content column

**Header (above card):**
- Top line: `⬡  RISC-V IMAGE CONVOLUTION  ·  FPGA COPROCESSOR INTERFACE` — 10px, `#00D4FF`, letter-spacing 0.3em
- Title: `UART CONNECTION SETUP` — 28px bold, `#E8F4FD`
- Subtitle: `Establish hardware link before loading images` — 11px, `#3A5068`
- Margin below header: 48px

**Card:**
- Background: `#0D1321`, border: 1px `#1E2D42`, border-radius: 12px
- Padding: 32px 40px, width: 420px
- Box-shadow: `0 0 40px #00000088`

Card contents (top to bottom):
1. Status row — 8px red dot + `NO HARDWARE DETECTED` text (`#FF4444`, 10px). Bottom border `#1E2D42`, padding-bottom 16px, margin-bottom 24px.
2. **COM Port** label (9px `#7A99B8`) + dropdown (full width minus refresh btn) + `⟳` refresh button (30×30, `#151F2E` bg, `#00D4FF` text)
3. **Baud Rate** label + full-width dropdown. Margin-bottom 24px.
4. Error text area (10px `#FF4444`, only shown on error)
5. **CONNECT** primary button — full width, 12px bold, padding 12px, letter-spacing 0.1em
6. `Skip — run in simulation mode` — centred 9px underlined `#3A5068` link

**Bottom footer:** `build 2025.06  |  UART 8N1  |  RISC-V RV32IM` — 9px `#3A5068`, absolutely positioned bottom-centre.

**Behaviour:**
- Clicking CONNECT shows `▶  CONNECTING...` with animated dots for ~1.6 seconds, then transitions to Stage 2.
- Port and baud selections are remembered in `localStorage`.
- Skip link goes directly to Stage 2 in simulation mode (yellow `SIMULATION MODE` status instead of green).

---

### Stage 2 — Main Dashboard

**Overall layout:** Fixed full window. Flex column: title bar → body. Body is flex row: sidebar → main content.

#### Title Bar (44px tall)
- Background: `#0D1321`, bottom border: 1px `#004466`
- Left: 4px wide `#00D4FF` stripe, then `⬡  RISC-V IMAGE CONVOLUTION  ·  FPGA COPROCESSOR INTERFACE` (11px bold `#00D4FF`, letter-spacing 0.05em)
- Right: `build 2025.06  |  UART 8N1  |  {PORT}  @  {BAUD}` (9px `#3A5068`)

#### Sidebar (240px wide, fixed)
Background `#0D1321`, right border 1px `#1E2D42`, overflow-y auto, padding 12px 14px.

Sections (each preceded by a `SectionLabel` — 2px wide `#00D4FF` stripe + 9px bold `#00D4FF` caps text):

1. **UART STATUS** — animated dot + status text + `⏻  DISCONNECT` danger button (full width)
2. **IMAGE SIZE** — 3 toggle cards stacked vertically:
   - `128 × 128` (default selected)
   - `512 × 512`
   - `1024 × 1024`
   - Selected state: bg `#004466`, border `#00D4FF`, text `#00D4FF`, bold
   - Unselected: bg `#151F2E`, border `#1E2D42`, text `#7A99B8`
   - Changing size resets entire session
3. **IMAGE INPUT** — `📂  SELECT IMAGE` ghost button + filename/size info below (9px `#7A99B8`)
4. **HARDWARE TARGET** — key/value pairs:
   | Key | Value |
   |---|---|
   | Architecture | RISC-V RV32IM |
   | Kernel | 3×3 Sobel |
   | Input | `{size}×{size} ×1` |
   | Output | `{size-2}×{size-2} ×1` |
   | Precision | UINT8 / Fixed |
   Keys: 9px `#3A5068`. Values: 9px `#00D4FF`.
5. **Footer** — `FPGA Coprocessor Interface  v1.0 / © 2025 Engineering Group 18` (8px `#3A5068`)

#### Main Content Area (flex column, fills remaining width)

**Top — Image Panels Row** (flex:1, flex-row, gap 10px, padding 12px 12px 8px)

Three image canvases separated by direction labels:

```
[ORIGINAL]  →SOFTWARE→  [SW OUTPUT]  →HARDWARE→  [HW OUTPUT]
```

Each canvas panel:
- Background: `#111927`, border 1px `#1E2D42`, border-radius 8px
- **Header bar** (background `#151F2E`, padding 6px 10px):
  - 3px left accent stripe (`#00D4FF`)
  - Title text: 9px bold `#7A99B8`, letter-spacing 0.05em
  - Badge (right): `NO DATA` default (9px `#3A5068` on `#0D1321`) → active: `#00D4FF` on `#004466`
- **Canvas area**: background `#080C14`, flex-centered, min-height ~280px
- Placeholder: subtle grid lines + crosshair + `NO IMAGE LOADED` text (all `#3A5068`)
- Loaded: image rendered pixel-accurately, with subtle 4px scanline overlay

Direction labels between panels:
- Text: `SOFTWARE` / `HARDWARE` (9px bold, rotated 90°)
- `SOFTWARE` colour: `#FFAA00`; `HARDWARE` colour: `#00D4FF`
- Arrow `→` below each label: 16px `#3A5068`

**Middle — Performance / Timing Panel** (padding 0 12px 8px)

Panel: background `#111927`, border 1px `#1E2D42`, border-radius 8px.

Header bar (background `#151F2E`):
- 3px left stripe colour: `#AA44FF`
- Title: `PERFORMANCE  ·  CYCLES  /  TIME` (9px bold `#7A99B8`)
- Right: `● MEASURING` blinking text (`#AA44FF`) when a run is in progress

Body (padding 10px 14px):
- **Three metric boxes** in a 3-column grid:
  | Box | Label | Value colour | Highlight |
  |---|---|---|---|
  | SOFTWARE TIME | ms + K cycles | `#FFAA00` | no |
  | HARDWARE TIME | ms + K cycles | `#00D4FF` | no |
  | SPEEDUP | `N.Nx` + cycle speedup | `#00E676` | yes — green glow border |
  
  Each box: bg `#151F2E`, border 1px `#1E2D42`, border-radius 6px, padding 8px 10px. Label 8px `#3A5068`, value 16px bold, sub 8px `#3A5068`. Highlighted box gets `${color}11` bg and `${color}44` border.

- **Relative bar chart** (shown after both runs complete):
  - Label + time value above each bar
  - SW bar: always 100% width, colour `#FFAA00`
  - HW bar: `(hwTime/swTime)*100`% width, colour `#00D4FF`
  - Bar height: 6px, background `#1E2D42`, border-radius 3px
  - Animated width transition: 0.6s ease

- Empty state: `Run HW and SW to compare performance` centred 10px `#3A5068`

**Bottom — Control Bar** (background `#0D1321`, top border 1px `#1E2D42`, padding 10px 12px)

Button row (flex, gap 10px, margin-bottom 8px):

| Button | Variant | Width | Label |
|---|---|---|---|
| RUN HW | primary (cyan) | 130px min | `▶  RUN  HW` / `⟳  RUNNING HW…` |
| RUN SW | warn (amber) | 130px min | `▶  RUN  SW` / `⟳  RUNNING SW…` |
| RESET | danger (red) | auto | `↺  RESET` |
| SAVE HW | ok (green) | auto | `💾  SAVE HW` |
| SAVE SW | ghost | auto | `💾  SAVE SW` |

Button states:
- **Disabled**: bg `#151F2E`, text `#3A5068`, border `#1E2D42`, cursor not-allowed
- **Hover**: slightly lighter bg, glow box-shadow `0 0 12px {borderColor}44`
- SAVE buttons only enabled after their respective run completes

Progress indicator (flex:1, right of buttons):
- Shows `ProgressBar` during active run — two-phase TX (cyan, left half) / RX (amber, right half) with centre divider tick
- Idle: status text (9px `#3A5068`)

**Console Log** (below button row):
- Background `#111927`, border 1px `#1E2D42`, border-radius 8px
- Header: amber 3px stripe + `SYSTEM LOG  /  UART MONITOR` (9px bold `#7A99B8`)
- Log area: 110px tall, overflow-y scroll, `Courier New` 10px, background `#080C14`
- Colours per log level:
  | Level | Colour |
  |---|---|
  | INFO | `#7A99B8` |
  | OK | `#00E676` |
  | WARN | `#FFAA00` |
  | ERR | `#FF4444` |
  | TX | `#00D4FF` |
  | RX | `#FF8C00` |
- Format: `[HH:MM:SS.mmm]` (`#3A5068`) + `[LEVEL]` + message (level colour)
- Auto-scrolls to bottom on new entry

---

## Interactions & Behaviour

### Connection Flow
1. App launches → Stage 1 connection screen
2. User selects port + baud → clicks CONNECT
3. 1.6s simulated handshake animation → Stage 2 loads
4. DISCONNECT button returns to Stage 1

### Image Load
1. Click `📂 SELECT IMAGE` → file picker (png/jpg/bmp/tif)
2. Image is converted to grayscale and resized to selected dimension (128/512/1024)
3. Displayed in Original canvas with badge updated
4. Output canvases cleared, timing panel reset

### Image Size Change
- Clicking a different size tile resets the entire session (clears canvases, logs, timing)
- Hardware target values update to reflect new size

### RUN HW
1. Sends image bytes over UART in 512-byte chunks
2. Progress bar fills TX half (0→50%) during send
3. Waits for RX bytes (126×126 / 510×510 / 1022×1022 depending on size)
4. Progress bar fills RX half (50→100%) during receive
5. Result rendered in HW Output canvas with Sobel edge-detected result
6. `hwTime` and `hwCycles` set; timing panel updates

### RUN SW
1. Runs Sobel 3×3 convolution in software on the same source image
2. Single-phase progress bar (0→100%)
3. Result rendered in SW Output canvas (subtle noise difference from HW to show deviation)
4. `swTime` and `swCycles` set; timing panel updates

### RESET
- Clears all canvases, log entries (keeps connection), resets progress, timing

### SAVE HW / SAVE SW
- Downloads the output canvas as `hw_{size}x{size}_output.png` / `sw_{size}x{size}_output.png`

### Persistence
- Connection (port, baud, simMode) stored in `localStorage` — survives page refresh
- Last image size stored and restored

---

## Design Tokens

```python
# Colours
BG_DEEP     = "#080C14"
BG_PANEL    = "#0D1321"
BG_CARD     = "#111927"
BG_SURFACE  = "#151F2E"
BG_BORDER   = "#1E2D42"

CYAN        = "#00D4FF"
CYAN_DIM    = "#004466"
CYAN_SEC    = "#0090CC"

WARN        = "#FFAA00"
WARN_DIM    = "#3D2800"

OK          = "#00E676"
OK_DIM      = "#003318"

ERR         = "#FF4444"
ERR_DIM     = "#3A0A0A"

PURPLE      = "#AA44FF"   # timing panel accent only

TEXT_PRI    = "#E8F4FD"
TEXT_SEC    = "#7A99B8"
TEXT_DIM    = "#3A5068"

# Typography (all Consolas or Courier New monospace)
FONT_TINY   = 8px
FONT_SMALL  = 9px
FONT_BODY   = 10px
FONT_UI     = 11px
FONT_BTN    = 12px
FONT_TITLE  = 28px bold   # Stage 1 only

# Geometry
SIDEBAR_W   = 240px
TITLEBAR_H  = 44px
BORDER_R    = 6–12px (cards 8–12px, buttons 6px)
GAP         = 10px (panels), 8–10px (buttons)
```

---

## Real UART Contract (from existing Python code)

```
TX: {size}×{size} raw uint8 bytes  (e.g. 16,384 for 128×128)
RX: {size-2}×{size-2} raw uint8 bytes  (e.g. 15,876 for 126×126)
Chunk size: 512 bytes
Baud: configurable (default 115200)
Timeout: 10 seconds
```

The existing `UARTWorker` class in `fpga_coprocessor_ui.py` handles this and can be reused directly. Only the UI layer needs to change.

---

## Software Convolution Reference Times (for timing panel)
These are approximate reference times for the comparison display:

| Size | SW (CPU) | HW (FPGA) | Speedup |
|---|---|---|---|
| 128×128 | ~24 ms | ~3 ms | ~7.8× |
| 512×512 | ~388 ms | ~18 ms | ~21× |
| 1024×1024 | ~1543 ms | ~72 ms | ~21× |

Measure actual times with `time.perf_counter()` and display in the panel.

---

## Files in This Package

| File | Description |
|---|---|
| `FPGA Coprocessor UI.html` | High-fidelity interactive prototype (React/HTML). Reference for all visual and interaction design. |
| `README.md` | This document. |

**Source codebase to modify:** `fpga_coprocessor_ui.py` (CustomTkinter, 1131 lines) in the `Image-Convulation-FPGA` project folder.
