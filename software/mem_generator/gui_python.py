"""
╔══════════════════════════════════════════════════════════════════════════════╗
║         RISC-V IMAGE CONVOLUTION FPGA COPROCESSOR — CONTROL INTERFACE       ║
║                  University Final Demo — Engineering Software Suite          ║
╚══════════════════════════════════════════════════════════════════════════════╝

Author  : FPGA Systems Engineering Group
Stack   : CustomTkinter · Pillow · NumPy · PySerial · Threading
Purpose : Premium GUI front-end for interfacing with a RISC-V convolution
          accelerator over UART.  Transmits a 128×128 grayscale image
          (16 384 bytes) and renders the 126×126 hardware-convolved result.

Keyboard Contract (UART):
  TX  → 16 384 raw uint8 bytes  (128×128 grayscale)
  RX  ← 15 876 raw uint8 bytes  (126×126 convolved output)
"""

from __future__ import annotations

import queue
import threading
import time
import tkinter as tk
from datetime import datetime
from pathlib import Path
from tkinter import filedialog, messagebox
from typing import Optional

import customtkinter as ctk
import numpy as np
import serial
import serial.tools.list_ports
from PIL import Image, ImageTk, ImageEnhance, ImageDraw

# ─────────────────────────────────────────────────────────────────────────────
#  DESIGN TOKENS  —  One place to rule all colours / sizes
# ─────────────────────────────────────────────────────────────────────────────
class Theme:
    # Base palette
    BG_DEEP      = "#080C14"   # deepest background
    BG_PANEL     = "#0D1321"   # sidebar / panels
    BG_CARD      = "#111927"   # card surfaces
    BG_SURFACE   = "#151F2E"   # elevated surfaces
    BG_BORDER    = "#1E2D42"   # subtle borders

    # Accent – electric cyan
    ACCENT_PRI   = "#00D4FF"   # primary neon cyan
    ACCENT_SEC   = "#0090CC"   # secondary/hover cyan
    ACCENT_DIM   = "#004466"   # dimmed accent fill

    # Accent – amber warning
    WARN         = "#FFAA00"
    WARN_DIM     = "#3D2800"

    # Accent – success green
    OK           = "#00E676"
    OK_DIM       = "#003318"

    # Accent – error red
    ERR          = "#FF4444"
    ERR_DIM      = "#3A0A0A"

    # Text
    TEXT_PRI     = "#E8F4FD"
    TEXT_SEC     = "#7A99B8"
    TEXT_DIM     = "#3A5068"
    TEXT_CODE    = "#A8D8EA"   # mono / log text

    # Typography
    FONT_DISPLAY = ("Consolas", 18, "bold")
    FONT_TITLE   = ("Consolas", 11, "bold")
    FONT_BODY    = ("Consolas", 10)
    FONT_SMALL   = ("Consolas", 9)
    FONT_MONO    = ("Courier New", 9)

    # Geometry
    SIDEBAR_W    = 260
    RADIUS       = 8
    PAD          = 16

# ─────────────────────────────────────────────────────────────────────────────
#  CUSTOM WIDGETS
# ─────────────────────────────────────────────────────────────────────────────

class StatusDot(ctk.CTkCanvas):
    """Animated pulsing status dot (green = connected, red = disconnected)."""

    _PULSE_STEPS  = 20
    _PULSE_PERIOD = 60   # ms per step

    def __init__(self, master: tk.Misc, **kwargs) -> None:
        super().__init__(
            master, width=14, height=14,
            bg=Theme.BG_PANEL, highlightthickness=0, **kwargs
        )
        self._connected  : bool        = False
        self._pulse_step : int         = 0
        self._pulse_id   : Optional[str] = None
        self._draw(1.0)

    # ── public API ──────────────────────────────────────────────────────────

    def set_connected(self, state: bool) -> None:
        self._connected = state
        if state:
            self._start_pulse()
        else:
            self._stop_pulse()
            self._draw(1.0)

    # ── internals ───────────────────────────────────────────────────────────

    def _draw(self, alpha: float) -> None:
        self.delete("all")
        color  = Theme.OK  if self._connected else Theme.ERR
        glow   = Theme.OK_DIM if self._connected else Theme.ERR_DIM
        r      = int(5 * alpha) + 2
        cx, cy = 7, 7
        # outer glow ring
        self.create_oval(cx-r-1, cy-r-1, cx+r+1, cy+r+1,
                         fill=glow, outline="")
        # core dot
        self.create_oval(cx-4, cy-4, cx+4, cy+4,
                         fill=color, outline=color)

    def _start_pulse(self) -> None:
        self._pulse_step = 0
        self._animate()

    def _stop_pulse(self) -> None:
        if self._pulse_id:
            self.after_cancel(self._pulse_id)
            self._pulse_id = None

    def _animate(self) -> None:
        import math
        phase = math.sin(math.pi * self._pulse_step / self._pulse_steps_half())
        alpha = 0.5 + 0.5 * abs(phase)
        self._draw(alpha)
        self._pulse_step = (self._pulse_step + 1) % (self._PULSE_STEPS * 2)
        self._pulse_id   = self.after(self._PULSE_PERIOD, self._animate)

    def _pulse_steps_half(self) -> int:
        return self._PULSE_STEPS


class ImageCanvas(ctk.CTkFrame):
    """
    Bordered dark-mode canvas with header label and placeholder grid graphic.
    Displays PIL images centred inside a fixed-size area.
    """

    def __init__(
        self,
        master: tk.Misc,
        title: str,
        canvas_size: int = 320,
        **kwargs,
    ) -> None:
        super().__init__(
            master,
            fg_color=Theme.BG_CARD,
            corner_radius=Theme.RADIUS,
            border_width=1,
            border_color=Theme.BG_BORDER,
            **kwargs,
        )
        self._size       = canvas_size
        self._photo_ref  : Optional[ImageTk.PhotoImage] = None   # keep reference!

        # ── header bar ──────────────────────────────────────────────────────
        hdr = ctk.CTkFrame(self, fg_color=Theme.BG_SURFACE,
                           corner_radius=0, height=32)
        hdr.pack(fill="x", padx=0, pady=(0, 0))
        hdr.pack_propagate(False)

        # tiny accent stripe
        stripe = tk.Frame(hdr, bg=Theme.ACCENT_PRI, width=3)
        stripe.pack(side="left", fill="y")

        ctk.CTkLabel(
            hdr, text=title,
            font=Theme.FONT_TITLE,
            text_color=Theme.TEXT_SEC,
        ).pack(side="left", padx=10, pady=6)

        self._badge = ctk.CTkLabel(
            hdr, text="NO DATA",
            font=Theme.FONT_SMALL,
            text_color=Theme.TEXT_DIM,
            fg_color=Theme.BG_PANEL,
            corner_radius=4,
            padx=6, pady=2,
        )
        self._badge.pack(side="right", padx=8, pady=6)

        # ── canvas area ─────────────────────────────────────────────────────
        canvas_bg = ctk.CTkFrame(self, fg_color=Theme.BG_DEEP, corner_radius=0)
        canvas_bg.pack(fill="both", expand=True, padx=12, pady=12)

        self._canvas = tk.Canvas(
            canvas_bg,
            width=canvas_size, height=canvas_size,
            bg=Theme.BG_DEEP, highlightthickness=0,
        )
        self._canvas.pack(expand=True)
        self._draw_placeholder()

    # ── public API ──────────────────────────────────────────────────────────

    def display_image(self, pil_img: Image.Image, badge: str = "") -> None:
        """Scale image to fit canvas and render it."""
        img = pil_img.copy()
        img.thumbnail((self._size, self._size), Image.LANCZOS)

        # convert to RGB for display (handles L mode too)
        img_rgb = img.convert("RGB")
        self._photo_ref = ImageTk.PhotoImage(img_rgb)

        self._canvas.delete("all")
        cx = self._size // 2
        cy = self._size // 2
        self._canvas.create_image(cx, cy, anchor="center", image=self._photo_ref)

        # subtle scan-line overlay effect
        for y in range(0, self._size, 4):
            self._canvas.create_line(
                0, y, self._size, y,
                fill="#000000", stipple="gray25"
            )

        if badge:
            self._badge.configure(
                text=badge,
                text_color=Theme.ACCENT_PRI,
                fg_color=Theme.ACCENT_DIM,
            )

    def clear(self) -> None:
        self._canvas.delete("all")
        self._draw_placeholder()
        self._badge.configure(
            text="NO DATA",
            text_color=Theme.TEXT_DIM,
            fg_color=Theme.BG_PANEL,
        )

    # ── internals ───────────────────────────────────────────────────────────

    def _draw_placeholder(self) -> None:
        """Subtle engineering-grid placeholder graphic."""
        s = self._size
        c = self._canvas
        c.delete("all")

        # grid lines
        step = 32
        for i in range(0, s + step, step):
            shade = Theme.BG_BORDER
            c.create_line(i, 0, i, s, fill=shade)
            c.create_line(0, i, s, i, fill=shade)

        # cross-hair
        mid = s // 2
        c.create_line(mid - 20, mid, mid + 20, mid, fill=Theme.TEXT_DIM, width=1)
        c.create_line(mid, mid - 20, mid, mid + 20, fill=Theme.TEXT_DIM, width=1)
        c.create_oval(mid - 4, mid - 4, mid + 4, mid + 4,
                      outline=Theme.TEXT_DIM, width=1)

        # label
        c.create_text(
            mid, mid + 36,
            text="NO IMAGE LOADED",
            fill=Theme.TEXT_DIM,
            font=Theme.FONT_SMALL,
        )


class ConsoleLog(ctk.CTkFrame):
    """Scrollable monospace log output with timestamp-coloured entries."""

    _COLORS = {
        "INFO" : Theme.TEXT_CODE,
        "OK"   : Theme.OK,
        "WARN" : Theme.WARN,
        "ERR"  : Theme.ERR,
        "TX"   : Theme.ACCENT_PRI,
        "RX"   : "#FF8C00",
    }

    def __init__(self, master: tk.Misc, **kwargs) -> None:
        super().__init__(master, fg_color=Theme.BG_CARD,
                         corner_radius=Theme.RADIUS,
                         border_width=1, border_color=Theme.BG_BORDER,
                         **kwargs)

        hdr = ctk.CTkFrame(self, fg_color=Theme.BG_SURFACE,
                           corner_radius=0, height=28)
        hdr.pack(fill="x")
        hdr.pack_propagate(False)
        tk.Frame(hdr, bg=Theme.WARN, width=3).pack(side="left", fill="y")
        ctk.CTkLabel(
            hdr, text="  SYSTEM LOG  /  UART MONITOR",
            font=Theme.FONT_SMALL, text_color=Theme.TEXT_SEC,
        ).pack(side="left", padx=6, pady=4)

        self._text = tk.Text(
            self,
            bg=Theme.BG_DEEP, fg=Theme.TEXT_CODE,
            font=Theme.FONT_MONO,
            relief="flat", bd=0,
            insertbackground=Theme.ACCENT_PRI,
            selectbackground=Theme.ACCENT_DIM,
            state="disabled",
            wrap="word",
            height=8,
        )
        self._text.pack(fill="both", expand=True, padx=6, pady=6)

        # define coloured tags
        for tag, colour in self._COLORS.items():
            self._text.tag_configure(f"tag_{tag}", foreground=colour)
        self._text.tag_configure("tag_TS",  foreground=Theme.TEXT_DIM)
        self._text.tag_configure("tag_BRK", foreground=Theme.BG_BORDER)

        self.log("INFO", "System initialised. Waiting for hardware connection.")

    # ── public API ──────────────────────────────────────────────────────────

    def log(self, level: str, message: str) -> None:
        ts    = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        tag   = f"tag_{level}"
        entry = f"[{ts}]  [{level:<4}]  {message}\n"

        self._text.configure(state="normal")
        self._text.insert("end", f"[{ts}]", "tag_TS")
        self._text.insert("end", f"  [{level:<4}]  ", tag)
        self._text.insert("end", f"{message}\n", tag)
        self._text.configure(state="disabled")
        self._text.see("end")

    def separator(self) -> None:
        self._text.configure(state="normal")
        self._text.insert("end",
            "─" * 72 + "\n", "tag_BRK")
        self._text.configure(state="disabled")
        self._text.see("end")


class SegmentedProgressBar(ctk.CTkFrame):
    """
    Two-phase segmented progress bar:
      phase 0 → 50 %  = TX  (cyan)
      phase 50 → 100 % = RX  (amber)
    """

    def __init__(self, master: tk.Misc, **kwargs) -> None:
        super().__init__(master, fg_color="transparent", **kwargs)
        self._pct : float = 0.0

        # track background
        self._track = tk.Canvas(
            self, height=10,
            bg=Theme.BG_BORDER, highlightthickness=0,
        )
        self._track.pack(fill="x", pady=(2, 0))
        self._track.bind("<Configure>", self._redraw)

        # label
        lbl_row = ctk.CTkFrame(self, fg_color="transparent")
        lbl_row.pack(fill="x")
        self._lbl_tx = ctk.CTkLabel(lbl_row, text="TX ──",
                                    font=Theme.FONT_SMALL,
                                    text_color=Theme.ACCENT_PRI)
        self._lbl_tx.pack(side="left")
        self._lbl_pct = ctk.CTkLabel(lbl_row, text="0 %",
                                     font=Theme.FONT_TITLE,
                                     text_color=Theme.TEXT_PRI)
        self._lbl_pct.pack(side="left", padx=6)
        self._lbl_rx = ctk.CTkLabel(lbl_row, text="── RX",
                                    font=Theme.FONT_SMALL,
                                    text_color=Theme.WARN)
        self._lbl_rx.pack(side="left")

    # ── public API ──────────────────────────────────────────────────────────

    def set_progress(self, pct: float) -> None:
        """pct in [0, 100]."""
        self._pct = max(0.0, min(100.0, pct))
        self._redraw()
        self._lbl_pct.configure(text=f"{int(self._pct)} %")

    def reset(self) -> None:
        self.set_progress(0)

    # ── internals ───────────────────────────────────────────────────────────

    def _redraw(self, _event=None) -> None:
        w = self._track.winfo_width()
        h = self._track.winfo_height() or 10
        if w < 2:
            return

        self._track.delete("all")
        # background
        self._track.create_rectangle(0, 0, w, h, fill=Theme.BG_BORDER, outline="")

        mid = w // 2
        fill_w = int(w * self._pct / 100)

        # TX half (cyan)
        tx_fill = min(fill_w, mid)
        if tx_fill > 0:
            self._track.create_rectangle(
                0, 0, tx_fill, h, fill=Theme.ACCENT_PRI, outline="")

        # RX half (amber) — only fills once pct > 50
        rx_start = max(fill_w, mid)
        if fill_w > mid:
            self._track.create_rectangle(
                mid, 0, fill_w, h, fill=Theme.WARN, outline="")

        # centre divider tick
        self._track.create_line(mid, 0, mid, h, fill=Theme.BG_DEEP, width=2)


# ─────────────────────────────────────────────────────────────────────────────
#  UART WORKER  (runs entirely in a background thread)
# ─────────────────────────────────────────────────────────────────────────────

class UARTWorker:
    """
    Handles all blocking serial I/O off the GUI thread.

    Communication is event-driven via a result queue that the GUI polls with
    `after()`.  No Tk calls are ever made from this thread.

    Queue message schema  →  dict with key 'type':
        { type: 'progress', value: float }
        { type: 'log',      level: str,   message: str }
        { type: 'result',   data: bytes }
        { type: 'error',    message: str }
    """

    TX_BYTES = 16_384   # 128 × 128 × 1
    RX_BYTES = 15_876   # 126 × 126 × 1
    CHUNK_SZ = 512      # write chunk size for smooth progress updates

    def __init__(
        self,
        port: str,
        baud: int,
        payload: bytes,
        result_q: queue.Queue,
    ) -> None:
        self._port     = port
        self._baud     = baud
        self._payload  = payload
        self._q        = result_q
        self._thread   = threading.Thread(
            target=self._run, daemon=True, name="UARTWorker"
        )

    def start(self) -> None:
        self._thread.start()

    # ── private ─────────────────────────────────────────────────────────────

    def _put(self, msg: dict) -> None:
        self._q.put_nowait(msg)

    def _run(self) -> None:
        try:
            self._put({"type": "log", "level": "INFO",
                       "message": f"Opening {self._port} @ {self._baud} baud …"})

            ser = serial.Serial(
                port=self._port,
                baudrate=self._baud,
                timeout=10,
                write_timeout=10,
            )

            # ── TX phase ────────────────────────────────────────────────────
            assert len(self._payload) == self.TX_BYTES, \
                f"Payload size mismatch: {len(self._payload)} ≠ {self.TX_BYTES}"

            self._put({"type": "log", "level": "TX",
                       "message": f"Transmitting {self.TX_BYTES:,} bytes "
                                  f"({self.TX_BYTES // 1024} KiB) → FPGA …"})

            sent = 0
            t_start = time.perf_counter()

            for offset in range(0, self.TX_BYTES, self.CHUNK_SZ):
                chunk = self._payload[offset : offset + self.CHUNK_SZ]
                ser.write(chunk)
                sent += len(chunk)
                pct   = (sent / self.TX_BYTES) * 50   # TX covers 0 → 50 %
                self._put({"type": "progress", "value": pct})

            tx_ms = (time.perf_counter() - t_start) * 1000
            self._put({"type": "log", "level": "TX",
                       "message": f"TX complete — {sent:,} bytes in {tx_ms:.1f} ms "
                                  f"({sent / (tx_ms / 1000) / 1024:.1f} KiB/s)"})

            # ── RX phase ────────────────────────────────────────────────────
            self._put({"type": "log", "level": "RX",
                       "message": f"Awaiting {self.RX_BYTES:,} bytes ← FPGA …"})

            rx_buf  = bytearray()
            t_rx    = time.perf_counter()

            while len(rx_buf) < self.RX_BYTES:
                needed  = self.RX_BYTES - len(rx_buf)
                chunk   = ser.read(min(self.CHUNK_SZ, needed))
                if not chunk:
                    raise TimeoutError(
                        f"UART RX timeout — received {len(rx_buf):,} / "
                        f"{self.RX_BYTES:,} bytes"
                    )
                rx_buf += chunk
                pct = 50 + (len(rx_buf) / self.RX_BYTES) * 50   # RX covers 50 → 100 %
                self._put({"type": "progress", "value": pct})

            rx_ms = (time.perf_counter() - t_rx) * 1000
            ser.close()

            self._put({"type": "log", "level": "RX",
                       "message": f"RX complete — {len(rx_buf):,} bytes in "
                                  f"{rx_ms:.1f} ms"})
            self._put({"type": "log", "level": "OK",
                       "message": "Hardware convolution complete ✓"})
            self._put({"type": "progress", "value": 100.0})
            self._put({"type": "result",   "data": bytes(rx_buf)})

        except serial.SerialException as exc:
            self._put({"type": "error",
                       "message": f"Serial error: {exc}"})
        except TimeoutError as exc:
            self._put({"type": "error",
                       "message": str(exc)})
        except AssertionError as exc:
            self._put({"type": "error",
                       "message": str(exc)})
        except Exception as exc:  # noqa: BLE001
            self._put({"type": "error",
                       "message": f"Unexpected error: {type(exc).__name__}: {exc}"})


# ─────────────────────────────────────────────────────────────────────────────
#  MAIN APPLICATION
# ─────────────────────────────────────────────────────────────────────────────

class FPGACoprocessorApp(ctk.CTk):
    """
    Top-level application window.

    Layout
    ──────
    ┌──────────────────────────────────────────────────────────┐
    │  TITLE BAR (custom drawn)                                │
    ├────────────┬─────────────────────────────────────────────┤
    │            │  MAIN DASHBOARD                             │
    │  SIDEBAR   │  ┌──────────────┐  ┌──────────────┐        │
    │            │  │ Original IMG │  │ HW Output    │        │
    │            │  └──────────────┘  └──────────────┘        │
    │            ├─────────────────────────────────────────────┤
    │            │  CONTROL BAR + PROGRESS + LOG               │
    └────────────┴─────────────────────────────────────────────┘
    """

    # ── init ────────────────────────────────────────────────────────────────

    def __init__(self) -> None:
        super().__init__()

        # global CTk theme
        ctk.set_appearance_mode("dark")
        ctk.set_default_color_theme("dark-blue")

        self._setup_window()
        self._build_ui()

        # state
        self._serial_conn : Optional[serial.Serial] = None
        self._source_img  : Optional[Image.Image]   = None
        self._result_q    : queue.Queue              = queue.Queue()
        self._running     : bool                     = False

        # start queue-poll loop
        self._poll_queue()

        # initial port scan
        self._refresh_ports()

    # ── window setup ────────────────────────────────────────────────────────

    def _setup_window(self) -> None:
        self.title("RISC-V FPGA Coprocessor Interface  ·  v1.0")
        self.geometry("1240x820")
        self.minsize(1100, 720)
        self.configure(fg_color=Theme.BG_DEEP)
        # custom icon fallback (no external file required)
        try:
            self.iconbitmap(default="")
        except Exception:
            pass

    # ── UI construction ─────────────────────────────────────────────────────

    def _build_ui(self) -> None:
        self._build_title_bar()

        body = ctk.CTkFrame(self, fg_color="transparent")
        body.pack(fill="both", expand=True)

        self._build_sidebar(body)
        self._build_main(body)

    def _build_title_bar(self) -> None:
        bar = ctk.CTkFrame(self, fg_color=Theme.BG_PANEL,
                           corner_radius=0, height=46)
        bar.pack(fill="x", side="top")
        bar.pack_propagate(False)

        # left accent stripe
        tk.Frame(bar, bg=Theme.ACCENT_PRI, width=4).pack(side="left", fill="y")

        ctk.CTkLabel(
            bar,
            text="  ⬡  RISC-V IMAGE CONVOLUTION  ·  FPGA COPROCESSOR INTERFACE",
            font=("Consolas", 12, "bold"),
            text_color=Theme.ACCENT_PRI,
        ).pack(side="left", padx=12)

        # right — build info
        ctk.CTkLabel(
            bar, text="build 2025.06  |  UART 8N1",
            font=Theme.FONT_SMALL, text_color=Theme.TEXT_DIM,
        ).pack(side="right", padx=16)

        # separator line
        tk.Frame(self, bg=Theme.ACCENT_DIM, height=1).pack(fill="x")

    def _build_sidebar(self, parent: ctk.CTkFrame) -> None:
        sb = ctk.CTkFrame(
            parent,
            width=Theme.SIDEBAR_W,
            fg_color=Theme.BG_PANEL,
            corner_radius=0,
        )
        sb.pack(side="left", fill="y", padx=0, pady=0)
        sb.pack_propagate(False)

        # right border line
        tk.Frame(sb, bg=Theme.BG_BORDER, width=1).pack(side="right", fill="y")

        inner = ctk.CTkFrame(sb, fg_color="transparent")
        inner.pack(fill="both", expand=True, padx=16, pady=16)

        # ── section: UART Config ─────────────────────────────────────────
        self._section_label(inner, "UART CONFIGURATION")

        ctk.CTkLabel(inner, text="COM Port",
                     font=Theme.FONT_SMALL, text_color=Theme.TEXT_SEC
                     ).pack(anchor="w", pady=(8, 2))

        port_row = ctk.CTkFrame(inner, fg_color="transparent")
        port_row.pack(fill="x")

        self._port_var = ctk.StringVar(value="")
        self._port_cb  = ctk.CTkComboBox(
            port_row,
            variable=self._port_var,
            values=[],
            fg_color=Theme.BG_SURFACE,
            border_color=Theme.BG_BORDER,
            button_color=Theme.ACCENT_DIM,
            button_hover_color=Theme.ACCENT_SEC,
            dropdown_fg_color=Theme.BG_CARD,
            font=Theme.FONT_BODY,
            text_color=Theme.TEXT_PRI,
            width=160,
        )
        self._port_cb.pack(side="left")

        ctk.CTkButton(
            port_row, text="⟳", width=30, height=30,
            fg_color=Theme.BG_SURFACE,
            hover_color=Theme.ACCENT_DIM,
            text_color=Theme.ACCENT_PRI,
            border_width=1, border_color=Theme.BG_BORDER,
            font=("Consolas", 14, "bold"),
            command=self._refresh_ports,
        ).pack(side="left", padx=(6, 0))

        ctk.CTkLabel(inner, text="Baud Rate",
                     font=Theme.FONT_SMALL, text_color=Theme.TEXT_SEC
                     ).pack(anchor="w", pady=(10, 2))

        self._baud_var = ctk.StringVar(value="115200")
        ctk.CTkComboBox(
            inner,
            variable=self._baud_var,
            values=["9600", "19200", "38400", "57600",
                    "115200", "230400", "460800", "921600"],
            fg_color=Theme.BG_SURFACE,
            border_color=Theme.BG_BORDER,
            button_color=Theme.ACCENT_DIM,
            button_hover_color=Theme.ACCENT_SEC,
            dropdown_fg_color=Theme.BG_CARD,
            font=Theme.FONT_BODY,
            text_color=Theme.TEXT_PRI,
            width=194,
        ).pack(anchor="w", pady=(0, 12))

        # ── Connect button + dot ─────────────────────────────────────────
        conn_row = ctk.CTkFrame(inner, fg_color="transparent")
        conn_row.pack(fill="x", pady=(0, 6))

        self._status_dot = StatusDot(conn_row)
        self._status_dot.pack(side="left", padx=(0, 8))

        self._conn_btn = ctk.CTkButton(
            conn_row,
            text="CONNECT",
            height=34,
            fg_color=Theme.ACCENT_DIM,
            hover_color=Theme.ACCENT_SEC,
            text_color=Theme.ACCENT_PRI,
            border_width=1, border_color=Theme.ACCENT_PRI,
            font=Theme.FONT_TITLE,
            corner_radius=6,
            command=self._toggle_connection,
        )
        self._conn_btn.pack(side="left", fill="x", expand=True)

        self._conn_status_lbl = ctk.CTkLabel(
            inner, text="●  DISCONNECTED",
            font=Theme.FONT_SMALL, text_color=Theme.ERR,
        )
        self._conn_status_lbl.pack(anchor="w", pady=(2, 16))

        # ── divider ──────────────────────────────────────────────────────
        tk.Frame(inner, bg=Theme.BG_BORDER, height=1).pack(fill="x", pady=8)

        # ── section: Image Input ─────────────────────────────────────────
        self._section_label(inner, "IMAGE INPUT")

        ctk.CTkButton(
            inner,
            text="  📂  SELECT IMAGE",
            height=38,
            fg_color=Theme.BG_SURFACE,
            hover_color=Theme.BG_CARD,
            text_color=Theme.TEXT_PRI,
            border_width=1, border_color=Theme.BG_BORDER,
            font=Theme.FONT_TITLE,
            corner_radius=6,
            command=self._select_image,
        ).pack(fill="x", pady=(8, 4))

        self._img_info_lbl = ctk.CTkLabel(
            inner, text="No file selected",
            font=Theme.FONT_SMALL, text_color=Theme.TEXT_DIM,
            wraplength=210, justify="left",
        )
        self._img_info_lbl.pack(anchor="w", pady=(4, 0))

        # ── divider ──────────────────────────────────────────────────────
        tk.Frame(inner, bg=Theme.BG_BORDER, height=1).pack(fill="x", pady=16)

        # ── section: HW Info ─────────────────────────────────────────────
        self._section_label(inner, "HARDWARE TARGET")

        info_items = [
            ("Architecture",  "RISC-V  RV32IM"),
            ("Kernel Size",   "3 × 3  (Sobel)"),
            ("Input Tensor",  "128 × 128 × 1"),
            ("Output Tensor", "126 × 126 × 1"),
            ("Precision",     "UINT8  / Fixed"),
        ]
        for label, val in info_items:
            row = ctk.CTkFrame(inner, fg_color="transparent")
            row.pack(fill="x", pady=1)
            ctk.CTkLabel(row, text=label,
                         font=Theme.FONT_SMALL, text_color=Theme.TEXT_DIM,
                         width=100, anchor="w").pack(side="left")
            ctk.CTkLabel(row, text=val,
                         font=Theme.FONT_SMALL, text_color=Theme.ACCENT_PRI,
                         anchor="w").pack(side="left")

        # ── spacer + version footer ───────────────────────────────────────
        ctk.CTkFrame(inner, fg_color="transparent").pack(fill="both", expand=True)

        ctk.CTkLabel(
            inner,
            text="FPGA Coprocessor Interface  v1.0\n© 2025 Engineering Dept.",
            font=("Consolas", 8), text_color=Theme.TEXT_DIM,
            justify="left",
        ).pack(anchor="sw", pady=(0, 4))

    def _build_main(self, parent: ctk.CTkFrame) -> None:
        main = ctk.CTkFrame(parent, fg_color="transparent")
        main.pack(side="left", fill="both", expand=True, padx=0, pady=0)

        # ── top dashboard ────────────────────────────────────────────────
        dash = ctk.CTkFrame(main, fg_color="transparent")
        dash.pack(fill="both", expand=True, padx=16, pady=(16, 8))

        self._canvas_orig = ImageCanvas(
            dash, "ORIGINAL IMAGE  ·  128 × 128  GRAYSCALE", canvas_size=300
        )
        self._canvas_orig.pack(side="left", fill="both", expand=True, padx=(0, 8))

        # centre divider with arrow
        mid_col = ctk.CTkFrame(dash, fg_color="transparent", width=40)
        mid_col.pack(side="left", fill="y")
        mid_col.pack_propagate(False)
        ctk.CTkLabel(
            mid_col, text="→\nUART\n→",
            font=("Consolas", 11, "bold"),
            text_color=Theme.ACCENT_DIM,
            justify="center",
        ).place(relx=0.5, rely=0.5, anchor="center")

        self._canvas_hw = ImageCanvas(
            dash, "HARDWARE OUTPUT  ·  126 × 126  CONVOLVED", canvas_size=300
        )
        self._canvas_hw.pack(side="left", fill="both", expand=True, padx=(8, 0))

        # ── control bar ──────────────────────────────────────────────────
        ctrl = ctk.CTkFrame(
            main, fg_color=Theme.BG_PANEL, corner_radius=0,
        )
        ctrl.pack(fill="x", padx=0, pady=0)
        tk.Frame(ctrl, bg=Theme.BG_BORDER, height=1).pack(fill="x")

        ctrl_inner = ctk.CTkFrame(ctrl, fg_color="transparent")
        ctrl_inner.pack(fill="x", padx=16, pady=12)

        # RUN button (left)
        self._run_btn = ctk.CTkButton(
            ctrl_inner,
            text="  ▶  RUN HARDWARE CONVOLUTION",
            height=42,
            width=300,
            state="disabled",
            fg_color=Theme.ACCENT_DIM,
            hover_color=Theme.ACCENT_SEC,
            text_color=Theme.ACCENT_PRI,
            border_width=1, border_color=Theme.ACCENT_PRI,
            font=("Consolas", 12, "bold"),
            corner_radius=6,
            command=self._run_convolution,
        )
        self._run_btn.pack(side="left", padx=(0, 16))

        # progress + status (right of run btn)
        pbar_col = ctk.CTkFrame(ctrl_inner, fg_color="transparent")
        pbar_col.pack(side="left", fill="x", expand=True)

        self._progress_bar = SegmentedProgressBar(pbar_col)
        self._progress_bar.pack(fill="x")

        self._status_lbl = ctk.CTkLabel(
            pbar_col, text="IDLE  —  Select image and connect hardware to begin.",
            font=Theme.FONT_SMALL, text_color=Theme.TEXT_DIM,
            anchor="w",
        )
        self._status_lbl.pack(anchor="w", pady=(2, 0))

        # ── console log ──────────────────────────────────────────────────
        self._log = ConsoleLog(main)
        self._log.pack(fill="x", padx=16, pady=(0, 12))

    # ── helpers ─────────────────────────────────────────────────────────────

    @staticmethod
    def _section_label(parent: ctk.CTkFrame, text: str) -> None:
        row = ctk.CTkFrame(parent, fg_color="transparent")
        row.pack(fill="x", pady=(6, 2))
        tk.Frame(row, bg=Theme.ACCENT_PRI, width=2, height=12).pack(
            side="left", padx=(0, 6))
        ctk.CTkLabel(
            row, text=text,
            font=("Consolas", 9, "bold"), text_color=Theme.ACCENT_PRI,
        ).pack(side="left")

    def _update_status(self, text: str, color: str = Theme.TEXT_SEC) -> None:
        self._status_lbl.configure(text=text, text_color=color)

    def _update_run_btn_state(self) -> None:
        """Enable run only when connected AND image loaded."""
        ready = (self._serial_conn is not None
                 and self._source_img is not None
                 and not self._running)
        self._run_btn.configure(state="normal" if ready else "disabled")

    # ── port management ─────────────────────────────────────────────────────

    def _refresh_ports(self) -> None:
        ports = [p.device for p in serial.tools.list_ports.comports()]
        if not ports:
            ports = ["(no ports found)"]
        self._port_cb.configure(values=ports)
        if ports:
            self._port_var.set(ports[0])
        self._log.log("INFO", f"Port scan: found {len(ports)} port(s)  →  "
                               + ", ".join(ports))

    # ── connection logic ────────────────────────────────────────────────────

    def _toggle_connection(self) -> None:
        if self._serial_conn is None:
            self._connect()
        else:
            self._disconnect()

    def _connect(self) -> None:
        port = self._port_var.get()
        baud = int(self._baud_var.get())

        if not port or port == "(no ports found)":
            messagebox.showwarning("No Port", "Please select a valid COM port.")
            return

        try:
            self._serial_conn = serial.Serial(port=port, baudrate=baud, timeout=10)
            self._log.separator()
            self._log.log("OK", f"Connected to {port} @ {baud} baud  ✓")
            self._conn_btn.configure(
                text="DISCONNECT",
                fg_color=Theme.ERR_DIM,
                hover_color="#5A1010",
                text_color=Theme.ERR,
                border_color=Theme.ERR,
            )
            self._status_dot.set_connected(True)
            self._conn_status_lbl.configure(
                text=f"●  {port}  CONNECTED", text_color=Theme.OK)
            self._update_status(f"Hardware connected on {port}.", Theme.OK)
        except serial.SerialException as exc:
            self._log.log("ERR", f"Connection failed: {exc}")
            messagebox.showerror("Connection Error", str(exc))
            self._serial_conn = None

        self._update_run_btn_state()

    def _disconnect(self) -> None:
        if self._serial_conn:
            try:
                self._serial_conn.close()
            except Exception:  # noqa: BLE001
                pass
            port = self._serial_conn.port
            self._serial_conn = None
            self._log.log("WARN", f"Disconnected from {port}.")

        self._conn_btn.configure(
            text="CONNECT",
            fg_color=Theme.ACCENT_DIM,
            hover_color=Theme.ACCENT_SEC,
            text_color=Theme.ACCENT_PRI,
            border_color=Theme.ACCENT_PRI,
        )
        self._status_dot.set_connected(False)
        self._conn_status_lbl.configure(text="●  DISCONNECTED", text_color=Theme.ERR)
        self._update_status("Disconnected.", Theme.TEXT_DIM)
        self._update_run_btn_state()

    # ── image selection ──────────────────────────────────────────────────────

    def _select_image(self) -> None:
        path = filedialog.askopenfilename(
            title="Select Input Image",
            filetypes=[
                ("Image Files", "*.png *.jpg *.jpeg *.bmp *.tif *.tiff *.webp"),
                ("All Files",   "*.*"),
            ],
        )
        if not path:
            return

        try:
            raw = Image.open(path)
            orig_size = raw.size
            orig_mode = raw.mode

            # ── preprocessing per hardware contract ──────────────────────
            img_gray = raw.convert("L")              # → 8-bit grayscale
            img_128  = img_gray.resize((128, 128), Image.LANCZOS)   # → 128×128
            self._source_img = img_128

            filename = Path(path).name
            self._img_info_lbl.configure(
                text=f"{filename}\n"
                     f"{orig_size[0]}×{orig_size[1]}  {orig_mode}  →  "
                     f"128×128  L\n"
                     f"{len(np.array(img_128).tobytes()):,} bytes",
                text_color=Theme.TEXT_PRI,
            )

            self._canvas_orig.display_image(img_128, badge="128×128 · L")
            self._canvas_hw.clear()
            self._progress_bar.reset()

            self._log.separator()
            self._log.log("INFO",
                          f"Image loaded: '{filename}'  "
                          f"({orig_size[0]}×{orig_size[1]} {orig_mode})  "
                          f"→ resized to 128×128 grayscale")
            self._log.log("INFO",
                          f"Payload ready: {UARTWorker.TX_BYTES:,} bytes  "
                          f"({UARTWorker.TX_BYTES // 1024} KiB)")

            self._update_status("Image loaded. Ready to run convolution.",
                                 Theme.TEXT_PRI)

        except Exception as exc:  # noqa: BLE001
            messagebox.showerror("Image Error", f"Failed to load image:\n{exc}")
            self._log.log("ERR", f"Image load failed: {exc}")

        self._update_run_btn_state()

    # ── convolution run ──────────────────────────────────────────────────────

    def _run_convolution(self) -> None:
        if self._source_img is None or self._serial_conn is None:
            return

        self._running = True
        self._update_run_btn_state()
        self._canvas_hw.clear()
        self._progress_bar.reset()

        payload = np.array(self._source_img).tobytes()
        assert len(payload) == UARTWorker.TX_BYTES, \
            f"BUG: payload = {len(payload)} bytes, expected {UARTWorker.TX_BYTES}"

        port = self._serial_conn.port
        baud = self._serial_conn.baudrate
        # close the connection held by the GUI; the worker opens its own
        self._serial_conn.close()

        self._log.separator()
        self._update_status("Transmitting to FPGA …", Theme.ACCENT_PRI)

        worker = UARTWorker(
            port    = port,
            baud    = baud,
            payload = payload,
            result_q= self._result_q,
        )
        worker.start()

    # ── queue polling (called every 50 ms on GUI thread) ────────────────────

    def _poll_queue(self) -> None:
        try:
            while True:
                msg = self._result_q.get_nowait()
                self._handle_message(msg)
        except queue.Empty:
            pass
        self.after(50, self._poll_queue)

    def _handle_message(self, msg: dict) -> None:
        kind = msg.get("type")

        if kind == "progress":
            self._progress_bar.set_progress(msg["value"])

        elif kind == "log":
            self._log.log(msg["level"], msg["message"])
            if msg["level"] == "TX":
                self._update_status("TX → Sending image data …", Theme.ACCENT_PRI)
            elif msg["level"] == "RX":
                self._update_status("RX ← Receiving convolved output …", Theme.WARN)

        elif kind == "result":
            self._on_result(msg["data"])

        elif kind == "error":
            self._on_error(msg["message"])

    def _on_result(self, raw: bytes) -> None:
        """Reconstruct image from received bytes and display it."""
        arr   = np.frombuffer(raw, dtype=np.uint8).reshape((126, 126))
        img   = Image.fromarray(arr, mode="L")

        self._canvas_hw.display_image(img, badge="126×126 · L")
        self._log.log("OK", "Processing complete. Output rendered on right canvas.")
        self._update_status("✓  Convolution complete — output displayed.", Theme.OK)
        self._progress_bar.set_progress(100)

        # re-open serial connection for next run
        try:
            port = self._port_var.get()
            baud = int(self._baud_var.get())
            self._serial_conn = serial.Serial(port=port, baudrate=baud, timeout=10)
        except serial.SerialException:
            self._serial_conn = None
            self._log.log("WARN",
                          "Could not re-open serial port after transfer.")

        self._running = False
        self._update_run_btn_state()

    def _on_error(self, message: str) -> None:
        self._log.log("ERR", message)
        self._update_status(f"ERROR: {message}", Theme.ERR)
        messagebox.showerror("Hardware Error", message)
        self._serial_conn = None
        self._running     = False
        self._update_run_btn_state()


# ─────────────────────────────────────────────────────────────────────────────
#  ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────

def main() -> None:
    app = FPGACoprocessorApp()
    app.mainloop()


if __name__ == "__main__":
    main()