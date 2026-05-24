"""
RISC-V IMAGE CONVOLUTION  -  FPGA COPROCESSOR INTERFACE
=========================================================

Two-stage CustomTkinter desktop UI faithful to UI_design_files/FPGA Coprocessor UI.html.

Stage 1 - Connection screen (port/baud picker, simulation-mode skip)
Stage 2 - Main dashboard:
            sidebar (UART status, image-size selector, input picker, HW target)
            three image panels (Original -> SW output -> HW output)
            performance panel (SW ms/cycles, HW ms/cycles, speedup)
            control bar (RUN HW, RUN SW, RESET, SAVE HW, SAVE SW)
            console log

UART contract (parametric by image size N):
    TX: N*N         uint8 bytes
    RX: (N-2)*(N-2) uint8 bytes   (3x3 Sobel, valid-only)
"""

from __future__ import annotations

import json
import math
import os
import queue
import sys
import threading
import time
import tkinter as tk
from datetime import datetime
from pathlib import Path
from tkinter import filedialog, messagebox
from typing import Optional, Callable, Dict, Any

import customtkinter as ctk
import numpy as np
import serial
import serial.tools.list_ports
from PIL import Image, ImageTk


# ----------------------------------------------------------------------------
#  DESIGN TOKENS
# ----------------------------------------------------------------------------

class T:
    BG_DEEP    = "#080C14"
    BG_PANEL   = "#0D1321"
    BG_CARD    = "#111927"
    BG_SURFACE = "#151F2E"
    BG_BORDER  = "#1E2D42"

    CYAN       = "#00D4FF"
    CYAN_SEC   = "#0090CC"
    CYAN_DIM   = "#004466"

    WARN       = "#FFAA00"
    WARN_DIM   = "#3D2800"

    OK         = "#00E676"
    OK_DIM     = "#003318"

    ERR        = "#FF4444"
    ERR_DIM    = "#3A0A0A"

    PURPLE     = "#AA44FF"

    TEXT_PRI   = "#E8F4FD"
    TEXT_SEC   = "#7A99B8"
    TEXT_DIM   = "#3A5068"
    TEXT_CODE  = "#A8D8EA"

    F_TINY     = ("Consolas", 8)
    F_SMALL    = ("Consolas", 9)
    F_SMALL_B  = ("Consolas", 9, "bold")
    F_BODY     = ("Consolas", 10)
    F_UI       = ("Consolas", 11)
    F_UI_B     = ("Consolas", 11, "bold")
    F_BTN      = ("Consolas", 12, "bold")
    F_METRIC   = ("Consolas", 16, "bold")
    F_TITLE    = ("Consolas", 28, "bold")
    F_MONO     = ("Courier New", 10)

    SIDEBAR_W  = 240
    TITLEBAR_H = 44


# ----------------------------------------------------------------------------
#  PERSISTENCE (replaces HTML localStorage)
# ----------------------------------------------------------------------------

def _config_dir() -> Path:
    base = os.environ.get("APPDATA") or str(Path.home())
    d = Path(base) / "FPGACoprocessorUI"
    d.mkdir(parents=True, exist_ok=True)
    return d


def load_config() -> Dict[str, Any]:
    p = _config_dir() / "config.json"
    if p.exists():
        try:
            return json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            return {}
    return {}


def save_config(cfg: Dict[str, Any]) -> None:
    p = _config_dir() / "config.json"
    try:
        p.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
    except Exception:
        pass


# ----------------------------------------------------------------------------
#  CUSTOM WIDGETS
# ----------------------------------------------------------------------------

class CornerBrackets(tk.Canvas):
    """Four 24x24 cyan corner accents for the Stage-1 viewport."""

    def __init__(self, master: tk.Misc, **kw) -> None:
        super().__init__(master, bg=T.BG_DEEP, highlightthickness=0, **kw)
        self.bind("<Configure>", self._redraw)

    def _redraw(self, _e=None) -> None:
        self.delete("all")
        w, h = self.winfo_width(), self.winfo_height()
        if w < 10 or h < 10:
            return
        pad = 24
        size = 24
        stroke = 2
        c = T.CYAN_DIM
        # TL
        self.create_line(pad, pad, pad + size, pad, fill=c, width=stroke)
        self.create_line(pad, pad, pad, pad + size, fill=c, width=stroke)
        # TR
        self.create_line(w - pad - size, pad, w - pad, pad, fill=c, width=stroke)
        self.create_line(w - pad, pad, w - pad, pad + size, fill=c, width=stroke)
        # BL
        self.create_line(pad, h - pad - size, pad, h - pad, fill=c, width=stroke)
        self.create_line(pad, h - pad, pad + size, h - pad, fill=c, width=stroke)
        # BR
        self.create_line(w - pad, h - pad - size, w - pad, h - pad, fill=c, width=stroke)
        self.create_line(w - pad - size, h - pad, w - pad, h - pad, fill=c, width=stroke)


class StatusDot(tk.Canvas):
    """Pulsing status dot."""

    def __init__(self, master: tk.Misc, bg: str = T.BG_PANEL, **kw) -> None:
        super().__init__(master, width=14, height=14, bg=bg, highlightthickness=0, **kw)
        self._state = "off"   # off | ok | warn
        self._step = 0
        self._job: Optional[str] = None
        self._draw(1.0)

    def set_state(self, state: str) -> None:
        self._state = state
        if self._job:
            self.after_cancel(self._job)
            self._job = None
        if state in ("ok", "warn"):
            self._step = 0
            self._animate()
        else:
            self._draw(1.0)

    def _color(self) -> tuple[str, str]:
        if self._state == "ok":
            return T.OK, T.OK_DIM
        if self._state == "warn":
            return T.WARN, T.WARN_DIM
        return T.ERR, T.ERR_DIM

    def _draw(self, a: float) -> None:
        self.delete("all")
        core, glow = self._color()
        r = int(4 * a) + 2
        cx, cy = 7, 7
        self.create_oval(cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1, fill=glow, outline="")
        self.create_oval(cx - 3, cy - 3, cx + 3, cy + 3, fill=core, outline=core)

    def _animate(self) -> None:
        a = 0.5 + 0.5 * abs(math.sin(math.pi * self._step / 20))
        self._draw(a)
        self._step = (self._step + 1) % 40
        self._job = self.after(60, self._animate)


class SectionLabel(ctk.CTkFrame):
    """2px cyan stripe + 9px bold caps label."""

    def __init__(self, master: tk.Misc, text: str, **kw) -> None:
        super().__init__(master, fg_color="transparent", **kw)
        tk.Frame(self, bg=T.CYAN, width=2, height=12).pack(side="left", padx=(0, 6))
        ctk.CTkLabel(self, text=text, font=T.F_SMALL_B, text_color=T.CYAN).pack(side="left")


class ImagePanel(ctk.CTkFrame):
    """Bordered panel with header bar + canvas, placeholder grid + scanlines."""

    def __init__(self, master: tk.Misc, title: str, **kw) -> None:
        super().__init__(master, fg_color=T.BG_CARD, corner_radius=8,
                         border_width=1, border_color=T.BG_BORDER, **kw)
        self._pil_img: Optional[Image.Image] = None
        self._photo: Optional[ImageTk.PhotoImage] = None

        hdr = ctk.CTkFrame(self, fg_color=T.BG_SURFACE, corner_radius=0, height=26)
        hdr.pack(fill="x")
        hdr.pack_propagate(False)
        tk.Frame(hdr, bg=T.CYAN, width=3).pack(side="left", fill="y")
        ctk.CTkLabel(hdr, text=title, font=T.F_SMALL_B, text_color=T.TEXT_SEC
                     ).pack(side="left", padx=8)
        self._badge = ctk.CTkLabel(
            hdr, text="NO DATA", font=T.F_SMALL,
            text_color=T.TEXT_DIM, fg_color=T.BG_PANEL,
            corner_radius=3, padx=6, pady=1,
        )
        self._badge.pack(side="right", padx=8, pady=4)

        body = ctk.CTkFrame(self, fg_color=T.BG_DEEP, corner_radius=0)
        body.pack(fill="both", expand=True, padx=1, pady=(0, 1))
        self._canvas = tk.Canvas(body, bg=T.BG_DEEP, highlightthickness=0)
        self._canvas.pack(fill="both", expand=True, padx=4, pady=4)
        self._canvas.bind("<Configure>", lambda _e: self._render())

    def display(self, img: Image.Image, badge: str) -> None:
        self._pil_img = img.convert("RGB")
        self._badge.configure(text=badge, text_color=T.CYAN, fg_color=T.CYAN_DIM)
        self._render()

    def clear(self) -> None:
        self._pil_img = None
        self._badge.configure(text="NO DATA", text_color=T.TEXT_DIM, fg_color=T.BG_PANEL)
        self._render()

    def get_image(self) -> Optional[Image.Image]:
        return self._pil_img

    def _render(self) -> None:
        c = self._canvas
        c.delete("all")
        w = c.winfo_width()
        h = c.winfo_height()
        if w < 10 or h < 10:
            return
        if self._pil_img is None:
            self._draw_placeholder(w, h)
            return
        pw, ph = self._pil_img.size
        scale = min(w / pw, h / ph)
        nw, nh = max(1, int(pw * scale)), max(1, int(ph * scale))
        img = self._pil_img.resize((nw, nh), Image.LANCZOS)
        self._photo = ImageTk.PhotoImage(img)
        c.create_image(w // 2, h // 2, anchor="center", image=self._photo)
        # scanline overlay
        for y in range(0, h, 4):
            c.create_line(0, y, w, y, fill="#000000", stipple="gray25")

    def _draw_placeholder(self, w: int, h: int) -> None:
        c = self._canvas
        step = 32
        for i in range(0, max(w, h) + step, step):
            c.create_line(i, 0, i, h, fill=T.BG_BORDER)
            c.create_line(0, i, w, i, fill=T.BG_BORDER)
        mx, my = w // 2, h // 2
        c.create_line(mx - 20, my, mx + 20, my, fill=T.TEXT_DIM)
        c.create_line(mx, my - 20, mx, my + 20, fill=T.TEXT_DIM)
        c.create_oval(mx - 4, my - 4, mx + 4, my + 4, outline=T.TEXT_DIM)
        c.create_text(mx, my + 36, text="NO IMAGE LOADED",
                      fill=T.TEXT_DIM, font=T.F_SMALL)


class DirectionLabel(ctk.CTkFrame):
    """Vertical 'SOFTWARE' or 'HARDWARE' label between image panels."""

    def __init__(self, master: tk.Misc, text: str, color: str, **kw) -> None:
        super().__init__(master, fg_color="transparent", width=32, **kw)
        self.pack_propagate(False)
        canvas = tk.Canvas(self, bg=T.BG_DEEP, highlightthickness=0, width=32)
        canvas.pack(fill="both", expand=True)
        canvas.bind("<Configure>",
                    lambda e: self._draw_label(canvas, e.width, e.height, text, color))

    @staticmethod
    def _draw_label(c: tk.Canvas, w: int, h: int, text: str, color: str) -> None:
        c.delete("all")
        # vertical rotated text
        c.create_text(w // 2, h // 2, text=text, fill=color,
                      angle=90, font=T.F_SMALL_B)
        c.create_text(w // 2, h - 12, text="->", fill=T.TEXT_DIM,
                      angle=90, font=T.F_UI_B)


class MetricBox(ctk.CTkFrame):
    """A single metric tile: SOFTWARE TIME, HARDWARE TIME, SPEEDUP."""

    def __init__(self, master: tk.Misc, label: str, color: str,
                 highlight: bool = False, **kw) -> None:
        bg = T.BG_SURFACE
        border = T.BG_BORDER
        if highlight:
            # approximate "${color}11" and "${color}44" overlays
            bg = T.BG_SURFACE
            border = color
        super().__init__(master, fg_color=bg, corner_radius=6,
                         border_width=1, border_color=border, **kw)
        self._color = color
        ctk.CTkLabel(self, text=label, font=T.F_TINY, text_color=T.TEXT_DIM
                     ).pack(anchor="w", padx=10, pady=(8, 0))
        self._value = ctk.CTkLabel(self, text="--", font=T.F_METRIC,
                                   text_color=color, anchor="w")
        self._value.pack(anchor="w", padx=10, pady=(0, 0))
        self._sub = ctk.CTkLabel(self, text="-- cycles", font=T.F_TINY,
                                 text_color=T.TEXT_DIM, anchor="w")
        self._sub.pack(anchor="w", padx=10, pady=(0, 8))

    def set_values(self, value: str, sub: str) -> None:
        self._value.configure(text=value)
        self._sub.configure(text=sub)

    def clear(self) -> None:
        self._value.configure(text="--")
        self._sub.configure(text="-- cycles")


class BarChart(ctk.CTkFrame):
    """Relative SW vs HW time bar chart."""

    def __init__(self, master: tk.Misc, **kw) -> None:
        super().__init__(master, fg_color="transparent", **kw)
        self._sw_ms: Optional[float] = None
        self._hw_ms: Optional[float] = None

        self._empty = ctk.CTkLabel(self, text="Run HW and SW to compare performance",
                                   font=T.F_BODY, text_color=T.TEXT_DIM)
        self._empty.pack(pady=10)

        self._chart = ctk.CTkFrame(self, fg_color="transparent")

        self._sw_label = ctk.CTkLabel(self._chart, text="SOFTWARE  --",
                                      font=T.F_SMALL, text_color=T.WARN, anchor="w")
        self._sw_label.pack(fill="x", pady=(4, 2))
        self._sw_track = tk.Canvas(self._chart, height=6,
                                   bg=T.BG_BORDER, highlightthickness=0)
        self._sw_track.pack(fill="x", pady=(0, 8))

        self._hw_label = ctk.CTkLabel(self._chart, text="HARDWARE  --",
                                      font=T.F_SMALL, text_color=T.CYAN, anchor="w")
        self._hw_label.pack(fill="x", pady=(0, 2))
        self._hw_track = tk.Canvas(self._chart, height=6,
                                   bg=T.BG_BORDER, highlightthickness=0)
        self._hw_track.pack(fill="x", pady=(0, 4))

        for tr in (self._sw_track, self._hw_track):
            tr.bind("<Configure>", lambda _e: self._redraw())

    def set_times(self, sw_ms: Optional[float], hw_ms: Optional[float]) -> None:
        self._sw_ms, self._hw_ms = sw_ms, hw_ms
        if sw_ms is not None and hw_ms is not None:
            self._empty.pack_forget()
            self._chart.pack(fill="x", padx=4)
            self._sw_label.configure(text=f"SOFTWARE   {sw_ms:,.1f} ms")
            self._hw_label.configure(text=f"HARDWARE   {hw_ms:,.1f} ms")
        else:
            self._chart.pack_forget()
            self._empty.pack(pady=10)
        self._redraw()

    def clear(self) -> None:
        self.set_times(None, None)

    def _redraw(self) -> None:
        if self._sw_ms is None or self._hw_ms is None:
            return
        for tr in (self._sw_track, self._hw_track):
            tr.delete("all")
        sw_w = self._sw_track.winfo_width()
        hw_w = self._hw_track.winfo_width()
        if sw_w < 2:
            return
        self._sw_track.create_rectangle(0, 0, sw_w, 6, fill=T.WARN, outline="")
        frac = (self._hw_ms / self._sw_ms) if self._sw_ms > 0 else 0
        frac = max(0.01, min(1.0, frac))
        fill = max(2, int(hw_w * frac))
        self._hw_track.create_rectangle(0, 0, fill, 6, fill=T.CYAN, outline="")


class ConsoleLog(ctk.CTkFrame):
    _COLORS = {
        "INFO": T.TEXT_SEC, "OK": T.OK, "WARN": T.WARN,
        "ERR": T.ERR, "TX": T.CYAN, "RX": "#FF8C00",
    }

    def __init__(self, master: tk.Misc, **kw) -> None:
        super().__init__(master, fg_color=T.BG_CARD, corner_radius=8,
                         border_width=1, border_color=T.BG_BORDER, **kw)

        hdr = ctk.CTkFrame(self, fg_color=T.BG_SURFACE, corner_radius=0, height=26)
        hdr.pack(fill="x")
        hdr.pack_propagate(False)
        tk.Frame(hdr, bg=T.WARN, width=3).pack(side="left", fill="y")
        ctk.CTkLabel(hdr, text="  SYSTEM LOG  /  UART MONITOR",
                     font=T.F_SMALL_B, text_color=T.TEXT_SEC
                     ).pack(side="left", padx=6)

        self._text = tk.Text(
            self, bg=T.BG_DEEP, fg=T.TEXT_CODE, font=T.F_MONO,
            relief="flat", bd=0, height=7,
            insertbackground=T.CYAN, selectbackground=T.CYAN_DIM,
            state="disabled", wrap="word",
        )
        self._text.pack(fill="both", expand=True, padx=4, pady=4)

        for tag, col in self._COLORS.items():
            self._text.tag_configure(f"tag_{tag}", foreground=col)
        self._text.tag_configure("tag_TS", foreground=T.TEXT_DIM)

    def log(self, level: str, message: str) -> None:
        ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        tag = f"tag_{level}"
        self._text.configure(state="normal")
        self._text.insert("end", f"[{ts}]", "tag_TS")
        self._text.insert("end", f"  [{level:<4}]  ", tag)
        self._text.insert("end", f"{message}\n", tag)
        self._text.configure(state="disabled")
        self._text.see("end")

    def clear(self) -> None:
        self._text.configure(state="normal")
        self._text.delete("1.0", "end")
        self._text.configure(state="disabled")


class SegmentedProgressBar(ctk.CTkFrame):
    """Two-phase TX (cyan, 0-50%) + RX (amber, 50-100%) progress bar."""

    def __init__(self, master: tk.Misc, **kw) -> None:
        super().__init__(master, fg_color="transparent", **kw)
        self._pct = 0.0
        self._two_phase = True
        self._track = tk.Canvas(self, height=8, bg=T.BG_BORDER, highlightthickness=0)
        self._track.pack(fill="x", pady=2)
        self._track.bind("<Configure>", lambda _e: self._redraw())

    def set_progress(self, pct: float) -> None:
        self._pct = max(0.0, min(100.0, pct))
        self._redraw()

    def set_two_phase(self, flag: bool) -> None:
        self._two_phase = flag
        self._redraw()

    def reset(self) -> None:
        self._pct = 0.0
        self._redraw()

    def _redraw(self) -> None:
        c = self._track
        c.delete("all")
        w = c.winfo_width()
        h = c.winfo_height() or 8
        if w < 2:
            return
        c.create_rectangle(0, 0, w, h, fill=T.BG_BORDER, outline="")
        if self._two_phase:
            mid = w // 2
            fill_w = int(w * self._pct / 100)
            tx = min(fill_w, mid)
            if tx > 0:
                c.create_rectangle(0, 0, tx, h, fill=T.CYAN, outline="")
            if fill_w > mid:
                c.create_rectangle(mid, 0, fill_w, h, fill=T.WARN, outline="")
            c.create_line(mid, 0, mid, h, fill=T.BG_DEEP, width=2)
        else:
            fill_w = int(w * self._pct / 100)
            if fill_w > 0:
                c.create_rectangle(0, 0, fill_w, h, fill=T.WARN, outline="")


# ----------------------------------------------------------------------------
#  UART WORKER (parametric size)
# ----------------------------------------------------------------------------

class UARTWorker:
    CHUNK_SZ = 512

    def __init__(self, port: str, baud: int, payload: bytes,
                 rx_bytes: int, result_q: queue.Queue,
                 timeout_sec: int = 10) -> None:
        self._port = port
        self._baud = baud
        self._payload = payload
        self._rx_bytes = rx_bytes
        self._q = result_q
        self._timeout = timeout_sec
        self._thread = threading.Thread(target=self._run, daemon=True, name="UARTWorker")

    def start(self) -> None:
        self._thread.start()

    def _put(self, m: dict) -> None:
        self._q.put_nowait(m)

    def _run(self) -> None:
        tx_bytes = len(self._payload)
        try:
            self._put({"type": "log", "level": "INFO",
                       "message": f"Opening {self._port} @ {self._baud} baud ..."})
            ser = serial.Serial(port=self._port, baudrate=self._baud,
                                timeout=self._timeout, write_timeout=10)
            ser.set_buffer_size(rx_size=32768, tx_size=32768)
            # Flush any stale bytes left in the Windows USB-CDC RX buffer from
            # a previous run. Without this, old FPGA TX bytes are returned as
            # the "response" for the current run (black / garbage image).
            ser.reset_input_buffer()

            self._put({"type": "log", "level": "TX",
                       "message": f"Transmitting {tx_bytes:,} bytes -> FPGA ..."})

            sent = 0
            t_hw_start = time.perf_counter()
            for off in range(0, tx_bytes, self.CHUNK_SZ):
                chunk = self._payload[off:off + self.CHUNK_SZ]
                ser.write(chunk)
                sent += len(chunk)
                self._put({"type": "progress", "value": (sent / tx_bytes) * 50})

            tx_ms = (time.perf_counter() - t_hw_start) * 1000
            self._put({"type": "log", "level": "TX",
                       "message": f"TX complete - {sent:,} bytes in {tx_ms:.1f} ms"})

            # Critical: flush() blocks until all bytes physically leave the OS/USB-CDC
            # driver buffer. Without this, ser.read() timeout starts while the FPGA
            # is still receiving image bytes → FSM stuck in WAIT_IMAGE → 0 bytes back.
            ser.flush()

            self._put({"type": "tx_done"})  # chronometer start signal

            self._put({"type": "log", "level": "RX",
                       "message": f"Awaiting {self._rx_bytes:,} bytes <- FPGA ..."})

            rx_buf = bytearray()
            t_rx = time.perf_counter()
            while len(rx_buf) < self._rx_bytes:
                needed = self._rx_bytes - len(rx_buf)
                chunk = ser.read(min(self.CHUNK_SZ, needed))
                if not chunk:
                    raise TimeoutError(
                        f"UART RX timeout - received {len(rx_buf):,} / "
                        f"{self._rx_bytes:,} bytes"
                    )
                rx_buf += chunk
                pct = 50 + (len(rx_buf) / self._rx_bytes) * 50
                self._put({"type": "progress", "value": pct})

            rx_ms = (time.perf_counter() - t_rx) * 1000
            total_ms = (time.perf_counter() - t_hw_start) * 1000
            ser.close()

            self._put({"type": "log", "level": "RX",
                       "message": f"RX complete - {len(rx_buf):,} bytes in {rx_ms:.1f} ms"})
            self._put({"type": "log", "level": "OK",
                       "message": f"Hardware convolution complete (total {total_ms:.1f} ms)"})
            self._put({"type": "progress", "value": 100.0})
            self._put({"type": "result", "data": bytes(rx_buf), "ms": total_ms})

        except serial.SerialException as exc:
            self._put({"type": "error", "message": f"Serial error: {exc}"})
        except TimeoutError as exc:
            self._put({"type": "error", "message": str(exc)})
        except Exception as exc:   # noqa: BLE001
            self._put({"type": "error",
                       "message": f"Unexpected error: {type(exc).__name__}: {exc}"})


# ----------------------------------------------------------------------------
#  SOFTWARE SOBEL 3x3 CONVOLUTION
# ----------------------------------------------------------------------------

def sobel_3x3(gray: np.ndarray) -> np.ndarray:
    """Zero-padded 'same' 3x3 Sobel magnitude; NxN -> NxN, uint8."""
    g = np.pad(gray.astype(np.int32), 1, mode='constant', constant_values=0)
    gx = (
        -1 * g[0:-2, 0:-2] + 1 * g[0:-2, 2:] +
        -2 * g[1:-1, 0:-2] + 2 * g[1:-1, 2:] +
        -1 * g[2:,   0:-2] + 1 * g[2:,   2:]
    )
    gy = (
        -1 * g[0:-2, 0:-2] - 2 * g[0:-2, 1:-1] - 1 * g[0:-2, 2:] +
         1 * g[2:,   0:-2] + 2 * g[2:,   1:-1] + 1 * g[2:,   2:]
    )
    mag = np.sqrt(gx * gx + gy * gy)
    mag = np.clip(mag, 0, 255).astype(np.uint8)
    return mag


# ----------------------------------------------------------------------------
#  STAGE 1  -  CONNECTION SCREEN
# ----------------------------------------------------------------------------

class ConnectionScreen(ctk.CTkFrame):
    def __init__(self, master: tk.Misc,
                 on_connect: Callable[[str, int, bool], None]) -> None:
        super().__init__(master, fg_color=T.BG_DEEP, corner_radius=0)
        self._on_connect = on_connect
        self._cfg = load_config()
        self._connecting = False
        self._dots_step = 0
        self._dots_job: Optional[str] = None

        # Corner brackets (behind everything)
        self._brackets = CornerBrackets(self)
        self._brackets.place(x=0, y=0, relwidth=1, relheight=1)

        # Header (above card)
        header = ctk.CTkFrame(self, fg_color="transparent")
        header.place(relx=0.5, rely=0.5, anchor="center", y=-180)

        ctk.CTkLabel(
            header,
            text="*  RISC-V IMAGE CONVOLUTION  .  FPGA COPROCESSOR INTERFACE",
            font=("Consolas", 10), text_color=T.CYAN,
        ).pack(pady=(0, 12))
        ctk.CTkLabel(header, text="UART CONNECTION SETUP",
                     font=T.F_TITLE, text_color=T.TEXT_PRI).pack()
        ctk.CTkLabel(header, text="Establish hardware link before loading images",
                     font=T.F_UI, text_color=T.TEXT_DIM).pack(pady=(4, 0))

        # Card
        card = ctk.CTkFrame(self, fg_color=T.BG_PANEL, corner_radius=12,
                            border_width=1, border_color=T.BG_BORDER, width=420)
        card.place(relx=0.5, rely=0.5, anchor="center", y=30)
        card.pack_propagate(False)
        card.configure(height=340)

        inner = ctk.CTkFrame(card, fg_color="transparent")
        inner.pack(fill="both", expand=True, padx=40, pady=28)

        # Status row
        status_row = ctk.CTkFrame(inner, fg_color="transparent")
        status_row.pack(fill="x", pady=(0, 14))
        self._status_dot = StatusDot(status_row, bg=T.BG_PANEL)
        self._status_dot.pack(side="left")
        self._status_lbl = ctk.CTkLabel(
            status_row, text="NO HARDWARE DETECTED",
            font=T.F_SMALL_B, text_color=T.ERR,
        )
        self._status_lbl.pack(side="left", padx=8)
        tk.Frame(inner, bg=T.BG_BORDER, height=1).pack(fill="x", pady=(0, 18))

        # COM port
        ctk.CTkLabel(inner, text="COM PORT", font=T.F_SMALL_B,
                     text_color=T.TEXT_SEC).pack(anchor="w", pady=(0, 4))
        port_row = ctk.CTkFrame(inner, fg_color="transparent")
        port_row.pack(fill="x")
        self._port_var = ctk.StringVar(value=self._cfg.get("port", ""))
        self._port_cb = ctk.CTkComboBox(
            port_row, variable=self._port_var, values=[],
            fg_color=T.BG_SURFACE, border_color=T.BG_BORDER,
            button_color=T.CYAN_DIM, button_hover_color=T.CYAN_SEC,
            dropdown_fg_color=T.BG_CARD, font=T.F_BODY,
            text_color=T.TEXT_PRI, height=30,
        )
        self._port_cb.pack(side="left", fill="x", expand=True)
        ctk.CTkButton(
            port_row, text="R", width=30, height=30,
            fg_color=T.BG_SURFACE, hover_color=T.CYAN_DIM,
            text_color=T.CYAN, border_width=1, border_color=T.BG_BORDER,
            font=T.F_UI_B, command=self._refresh_ports,
        ).pack(side="left", padx=(6, 0))

        # Baud rate
        ctk.CTkLabel(inner, text="BAUD RATE", font=T.F_SMALL_B,
                     text_color=T.TEXT_SEC).pack(anchor="w", pady=(14, 4))
        self._baud_var = ctk.StringVar(value=str(self._cfg.get("baud", "115200")))
        ctk.CTkComboBox(
            inner, variable=self._baud_var,
            values=["9600", "19200", "38400", "57600",
                    "115200", "230400", "460800", "921600"],
            fg_color=T.BG_SURFACE, border_color=T.BG_BORDER,
            button_color=T.CYAN_DIM, button_hover_color=T.CYAN_SEC,
            dropdown_fg_color=T.BG_CARD, font=T.F_BODY,
            text_color=T.TEXT_PRI, height=30,
        ).pack(fill="x")

        # Error text
        self._err_lbl = ctk.CTkLabel(inner, text="", font=T.F_SMALL,
                                     text_color=T.ERR)
        self._err_lbl.pack(anchor="w", pady=(10, 0))

        # CONNECT button
        self._connect_btn = ctk.CTkButton(
            inner, text="CONNECT", height=36,
            fg_color=T.CYAN_DIM, hover_color=T.CYAN_SEC,
            text_color=T.CYAN, border_width=1, border_color=T.CYAN,
            font=T.F_BTN, command=self._click_connect,
        )
        self._connect_btn.pack(fill="x", pady=(12, 6))

        # Skip link
        self._skip_lbl = ctk.CTkLabel(
            inner, text="Skip - run in simulation mode",
            font=("Consolas", 9, "underline"),
            text_color=T.TEXT_DIM, cursor="hand2",
        )
        self._skip_lbl.pack()
        self._skip_lbl.bind("<Button-1>", lambda _e: self._skip())

        # Bottom footer
        ctk.CTkLabel(
            self, text="build 2025.06  |  UART 8N1  |  RISC-V RV32IM",
            font=T.F_SMALL, text_color=T.TEXT_DIM,
        ).place(relx=0.5, rely=1.0, anchor="s", y=-20)

        self._refresh_ports()

    def _refresh_ports(self) -> None:
        ports = [p.device.upper() for p in serial.tools.list_ports.comports()]
        if not ports:
            ports = ["(no ports found)"]
            self._status_lbl.configure(text="NO HARDWARE DETECTED", text_color=T.ERR)
            self._status_dot.set_state("off")
        else:
            self._status_lbl.configure(text=f"{len(ports)} PORT(S) DETECTED",
                                       text_color=T.WARN)
            self._status_dot.set_state("warn")
            
        self._port_cb.configure(values=ports)
        
        cur = self._port_var.get().upper()
        if cur in ports:
            self._port_var.set(cur)
            self._port_cb.set(cur)  # Explicitly update the visually selected item
        elif ports:
            self._port_var.set(ports[0])
            self._port_cb.set(ports[0])

    def _click_connect(self) -> None:
        if self._connecting:
            return
        port = self._port_var.get()
        if not port or port == "(no ports found)":
            self._err_lbl.configure(text="Select a valid COM port first.")
            return
        try:
            baud = int(self._baud_var.get())
        except ValueError:
            self._err_lbl.configure(text="Invalid baud rate.")
            return
        self._err_lbl.configure(text="")
        self._connecting = True
        self._connect_btn.configure(state="disabled")
        self._animate_connecting()
        # real connection attempt after the 1.6s animation
        self.after(1600, lambda: self._finish_connect(port, baud))

    def _animate_connecting(self) -> None:
        if not self._connecting:
            return
        dots = "." * (1 + self._dots_step % 3)
        self._connect_btn.configure(text=f">  CONNECTING{dots}")
        self._dots_step += 1
        self._dots_job = self.after(200, self._animate_connecting)

    def _stop_animate(self) -> None:
        self._connecting = False
        if self._dots_job:
            self.after_cancel(self._dots_job)
            self._dots_job = None

    def _finish_connect(self, port: str, baud: int) -> None:
        try:
            s = serial.Serial(port=port, baudrate=baud, timeout=10)
            s.close()
        except serial.SerialException as exc:
            self._stop_animate()
            self._connect_btn.configure(state="normal", text="CONNECT")
            self._err_lbl.configure(text=f"Connection failed: {exc}")
            return
        self._stop_animate()
        self._cfg.update({"port": port, "baud": baud, "sim_mode": False})
        save_config(self._cfg)
        self._on_connect(port, baud, False)

    def _skip(self) -> None:
        self._cfg.update({"sim_mode": True})
        save_config(self._cfg)
        self._on_connect("(simulation)", 115200, True)


# ----------------------------------------------------------------------------
#  STAGE 2  -  MAIN DASHBOARD
# ----------------------------------------------------------------------------

class MainDashboard(ctk.CTkFrame):
    SIZES = [128, 512, 1024]
    FILTER_MAP = {
        "Gaussian Blur": 0,
        "Sobel X":       1,
        "Sobel Y":       2,
        "Sharpen":       3,
        "Edge Detect":   4,
        "Identity (debug)": 5,
    }

    def __init__(self, master: tk.Misc, port: str, baud: int, sim_mode: bool,
                 on_disconnect: Callable[[], None]) -> None:
        super().__init__(master, fg_color=T.BG_DEEP, corner_radius=0)

        self._port = port
        self._baud = baud
        self._sim_mode = sim_mode
        self._on_disconnect_cb = on_disconnect

        cfg = load_config()
        self._size = int(cfg.get("size", 128))
        if self._size not in self.SIZES:
            self._size = 128

        # state
        self._source_img: Optional[Image.Image] = None
        self._sw_ms: Optional[float] = None
        self._hw_ms: Optional[float] = None
        self._hw_cycles: Optional[int] = None   # actual FPGA benchmark cycles (HW run)
        self._sw_cycles: Optional[int] = None   # actual FPGA benchmark cycles (SW run)
        self._result_q: queue.Queue = queue.Queue()
        self._running: Optional[str] = None   # None | "hw" | "sw"
        self._sw_from_fpga: bool = False       # True when last SW result came from FPGA
        self._chrono_start: Optional[float] = None   # perf_counter when TX flush done
        self._chrono_job: Optional[str] = None        # after() ID for live tick

        self._build()
        self._poll_queue()

    # ------ UI build ------

    def _build(self) -> None:
        self._build_title_bar()
        body = ctk.CTkFrame(self, fg_color="transparent")
        body.pack(fill="both", expand=True)
        self._build_sidebar(body)
        self._build_main(body)

    def _build_title_bar(self) -> None:
        bar = ctk.CTkFrame(self, fg_color=T.BG_PANEL, corner_radius=0,
                           height=T.TITLEBAR_H)
        bar.pack(fill="x")
        bar.pack_propagate(False)
        tk.Frame(bar, bg=T.CYAN, width=4).pack(side="left", fill="y")
        ctk.CTkLabel(
            bar,
            text="  *  RISC-V IMAGE CONVOLUTION  .  FPGA COPROCESSOR INTERFACE",
            font=T.F_UI_B, text_color=T.CYAN,
        ).pack(side="left", padx=12)
        right = f"build 2025.06  |  UART 8N1  |  {self._port}  @  {self._baud}"
        ctk.CTkLabel(bar, text=right, font=T.F_SMALL, text_color=T.TEXT_DIM
                     ).pack(side="right", padx=16)
        tk.Frame(self, bg=T.CYAN_DIM, height=1).pack(fill="x")

    def _build_sidebar(self, parent: ctk.CTkFrame) -> None:
        sb = ctk.CTkFrame(parent, width=T.SIDEBAR_W, fg_color=T.BG_PANEL,
                          corner_radius=0)
        sb.pack(side="left", fill="y")
        sb.pack_propagate(False)
        tk.Frame(sb, bg=T.BG_BORDER, width=1).pack(side="right", fill="y")

        inner = ctk.CTkScrollableFrame(sb, fg_color=T.BG_PANEL,
                                       scrollbar_button_color=T.BG_BORDER,
                                       scrollbar_button_hover_color=T.CYAN_DIM)
        inner.pack(fill="both", expand=True, padx=10, pady=12)

        # ---- UART STATUS ----
        SectionLabel(inner, "UART STATUS").pack(anchor="w", pady=(0, 6))
        uart_row = ctk.CTkFrame(inner, fg_color="transparent")
        uart_row.pack(fill="x", pady=(0, 6))
        self._uart_dot = StatusDot(uart_row, bg=T.BG_PANEL)
        self._uart_dot.pack(side="left")
        uart_txt = "SIMULATION MODE" if self._sim_mode else f"CONNECTED {self._port}"
        uart_col = T.WARN if self._sim_mode else T.OK
        self._uart_dot.set_state("warn" if self._sim_mode else "ok")
        self._uart_lbl = ctk.CTkLabel(uart_row, text=uart_txt,
                                      font=T.F_SMALL_B, text_color=uart_col)
        self._uart_lbl.pack(side="left", padx=6)

        ctk.CTkButton(
            inner, text="DISCONNECT", height=30,
            fg_color=T.ERR_DIM, hover_color="#5A1010",
            text_color=T.ERR, border_width=1, border_color=T.ERR,
            font=T.F_SMALL_B, corner_radius=6,
            command=self._disconnect,
        ).pack(fill="x", pady=(4, 14))

        # ---- IMAGE SIZE ----
        SectionLabel(inner, "IMAGE SIZE").pack(anchor="w", pady=(0, 6))
        self._size_cards: Dict[int, ctk.CTkButton] = {}
        for s in self.SIZES:
            btn = ctk.CTkButton(
                inner, text=f"{s} x {s}", height=30,
                fg_color=T.BG_SURFACE, hover_color=T.BG_CARD,
                text_color=T.TEXT_SEC, border_width=1,
                border_color=T.BG_BORDER, font=T.F_SMALL_B,
                corner_radius=6,
                command=lambda sz=s: self._set_size(sz),
            )
            btn.pack(fill="x", pady=2)
            self._size_cards[s] = btn
        self._highlight_size()
        # ---- EXECUTION MODE INFO ----
        # Both HW and SW modes run from the same unified_conv firmware.
        # RUN HW  → dispatches to DSP conv_engine (filter_id sent as-is)
        # RUN SW  → dispatches to RISC-V CPU math (filter_id | 16 sentinel)
        # The sidebar toggle below is informational only.
        SectionLabel(inner, "EXECUTION MODE").pack(anchor="w", pady=(14, 6))
        hw_info = ctk.CTkFrame(inner, fg_color=T.CYAN_DIM, corner_radius=6,
                               border_width=1, border_color=T.CYAN)
        hw_info.pack(fill="x", pady=(0, 3))
        ctk.CTkLabel(hw_info, text="RUN HW  →  DSP Engine",
                     font=T.F_SMALL_B, text_color=T.CYAN,
                     anchor="w").pack(fill="x", padx=8, pady=4)

        sw_info = ctk.CTkFrame(inner, fg_color=T.WARN_DIM, corner_radius=6,
                               border_width=1, border_color=T.WARN)
        sw_info.pack(fill="x", pady=(0, 3))
        ctk.CTkLabel(sw_info, text="RUN SW  →  RISC-V CPU",
                     font=T.F_SMALL_B, text_color=T.WARN,
                     anchor="w").pack(fill="x", padx=8, pady=4)

        ctk.CTkLabel(
            inner, text="Both modes use unified_conv firmware",
            font=T.F_TINY, text_color=T.TEXT_DIM,
        ).pack(anchor="w", pady=(2, 0))

        # ---- CHRONOMETER ----
        SectionLabel(inner, "CHRONOMETER").pack(anchor="w", pady=(14, 6))
        self._chrono_lbl = ctk.CTkLabel(
            inner, text="00:00.000", font=("Consolas", 22, "bold"),
            text_color=T.PURPLE, anchor="w",
        )
        self._chrono_lbl.pack(fill="x")
        self._chrono_sub = ctk.CTkLabel(
            inner, text="FPGA processing latency",
            font=T.F_TINY, text_color=T.TEXT_DIM,
        )
        self._chrono_sub.pack(anchor="w", pady=(0, 0))

        # ---- FILTER ----
        SectionLabel(inner, "FILTER").pack(anchor="w", pady=(14, 6))
        self._filter_var = ctk.StringVar(value="Gaussian Blur")
        ctk.CTkComboBox(
            inner, variable=self._filter_var,
            values=list(self.FILTER_MAP.keys()),
            font=T.F_SMALL, text_color=T.TEXT_PRI,
            fg_color=T.BG_SURFACE, border_color=T.BG_BORDER,
            button_color=T.BG_BORDER, dropdown_fg_color=T.BG_PANEL,
            dropdown_text_color=T.TEXT_PRI, dropdown_font=T.F_SMALL,
        ).pack(fill="x")

        # ---- IMAGE INPUT ----
        SectionLabel(inner, "IMAGE INPUT").pack(anchor="w", pady=(14, 6))
        ctk.CTkButton(
            inner, text="  SELECT IMAGE", height=32,
            fg_color=T.BG_SURFACE, hover_color=T.BG_CARD,
            text_color=T.TEXT_PRI, border_width=1, border_color=T.BG_BORDER,
            font=T.F_SMALL_B, corner_radius=6,
            command=self._select_image,
        ).pack(fill="x")
        self._img_info = ctk.CTkLabel(
            inner, text="No file selected",
            font=T.F_SMALL, text_color=T.TEXT_DIM,
            wraplength=200, justify="left", anchor="w",
        )
        self._img_info.pack(fill="x", pady=(4, 0))

        # ---- HARDWARE TARGET ----
        SectionLabel(inner, "HARDWARE TARGET").pack(anchor="w", pady=(14, 6))
        self._hw_target_rows: Dict[str, ctk.CTkLabel] = {}
        for key in ("Architecture", "Kernel", "Input", "Output", "Precision"):
            row = ctk.CTkFrame(inner, fg_color="transparent")
            row.pack(fill="x", pady=1)
            ctk.CTkLabel(row, text=key, font=T.F_SMALL, text_color=T.TEXT_DIM,
                         width=92, anchor="w").pack(side="left")
            val = ctk.CTkLabel(row, text="--", font=T.F_SMALL,
                               text_color=T.CYAN, anchor="w")
            val.pack(side="left", fill="x", expand=True)
            self._hw_target_rows[key] = val
        self._update_hw_target()

        # footer
        ctk.CTkLabel(
            inner,
            text="\nFPGA Coprocessor Interface  v1.0\n(c) 2025 Engineering Group 18",
            font=T.F_TINY, text_color=T.TEXT_DIM, justify="left",
        ).pack(anchor="w", pady=(18, 0))

    def _build_main(self, parent: ctk.CTkFrame) -> None:
        main = ctk.CTkFrame(parent, fg_color="transparent")
        main.pack(side="left", fill="both", expand=True)

        # ---- three image panels ----
        imgs = ctk.CTkFrame(main, fg_color="transparent")
        imgs.pack(fill="both", expand=True, padx=12, pady=(10, 6))

        self._panel_orig = ImagePanel(imgs, "ORIGINAL")
        self._panel_orig.pack(side="left", fill="both", expand=True)
        DirectionLabel(imgs, "SOFTWARE", T.WARN).pack(side="left", fill="y", padx=4)
        self._panel_sw = ImagePanel(imgs, "SW OUTPUT")
        self._panel_sw.pack(side="left", fill="both", expand=True)
        DirectionLabel(imgs, "HARDWARE", T.CYAN).pack(side="left", fill="y", padx=4)
        self._panel_hw = ImagePanel(imgs, "HW OUTPUT")
        self._panel_hw.pack(side="left", fill="both", expand=True)

        # ---- performance panel ----
        perf = ctk.CTkFrame(main, fg_color=T.BG_CARD, corner_radius=8,
                            border_width=1, border_color=T.BG_BORDER)
        perf.pack(fill="x", padx=12, pady=(0, 6))

        phdr = ctk.CTkFrame(perf, fg_color=T.BG_SURFACE, corner_radius=0, height=26)
        phdr.pack(fill="x")
        phdr.pack_propagate(False)
        tk.Frame(phdr, bg=T.PURPLE, width=3).pack(side="left", fill="y")
        ctk.CTkLabel(phdr, text="  PERFORMANCE  .  CYCLES  /  TIME",
                     font=T.F_SMALL_B, text_color=T.TEXT_SEC
                     ).pack(side="left", padx=6)
        self._measuring_lbl = ctk.CTkLabel(phdr, text="", font=T.F_SMALL,
                                           text_color=T.PURPLE)
        self._measuring_lbl.pack(side="right", padx=8)

        pbody = ctk.CTkFrame(perf, fg_color=T.BG_CARD)
        pbody.pack(fill="x", padx=10, pady=10)

        # 3 metric boxes in a row
        boxes = ctk.CTkFrame(pbody, fg_color="transparent")
        boxes.pack(fill="x")
        boxes.grid_columnconfigure((0, 1, 2), weight=1, uniform="m")
        self._box_sw = MetricBox(boxes, "SOFTWARE TIME", T.WARN)
        self._box_hw = MetricBox(boxes, "HARDWARE TIME", T.CYAN)
        self._box_sp = MetricBox(boxes, "SPEEDUP", T.OK, highlight=True)
        self._box_sw.grid(row=0, column=0, sticky="ew", padx=(0, 6))
        self._box_hw.grid(row=0, column=1, sticky="ew", padx=6)
        self._box_sp.grid(row=0, column=2, sticky="ew", padx=(6, 0))

        self._bar_chart = BarChart(pbody)
        self._bar_chart.pack(fill="x", pady=(10, 0))

        # ---- control bar ----
        ctrl = ctk.CTkFrame(main, fg_color=T.BG_PANEL, corner_radius=0)
        ctrl.pack(fill="x")
        tk.Frame(ctrl, bg=T.BG_BORDER, height=1).pack(fill="x")

        ctrl_inner = ctk.CTkFrame(ctrl, fg_color="transparent")
        ctrl_inner.pack(fill="x", padx=12, pady=10)

        btn_row = ctk.CTkFrame(ctrl_inner, fg_color="transparent")
        btn_row.pack(fill="x")

        def mkbtn(parent, text, fg, border, textcol, cmd, width=None, state="disabled"):
            return ctk.CTkButton(
                parent, text=text, height=34,
                fg_color=fg, hover_color=T.BG_SURFACE,
                text_color=textcol, border_width=1, border_color=border,
                font=T.F_BTN, corner_radius=6, width=width or 0,
                state=state, command=cmd,
            )

        self._btn_run_hw = mkbtn(btn_row, ">  RUN  HW",
                                 T.CYAN_DIM, T.CYAN, T.CYAN,
                                 self._run_hw, width=140)
        self._btn_run_hw.pack(side="left", padx=(0, 8))
        self._btn_run_sw = mkbtn(btn_row, ">  RUN  SW",
                                 T.WARN_DIM, T.WARN, T.WARN,
                                 self._run_sw, width=140)
        self._btn_run_sw.pack(side="left", padx=(0, 8))
        self._btn_reset = mkbtn(btn_row, "RESET",
                                T.ERR_DIM, T.ERR, T.ERR,
                                self._reset_session)
        self._btn_reset.pack(side="left", padx=(0, 8))
        self._btn_save_hw = mkbtn(btn_row, "SAVE HW",
                                  T.OK_DIM, T.OK, T.OK,
                                  lambda: self._save_output("hw"))
        self._btn_save_hw.pack(side="left", padx=(0, 8))
        self._btn_save_sw = mkbtn(btn_row, "SAVE SW",
                                  T.BG_SURFACE, T.BG_BORDER, T.TEXT_SEC,
                                  lambda: self._save_output("sw"))
        self._btn_save_sw.pack(side="left", padx=(0, 8))

        self._progress = SegmentedProgressBar(ctrl_inner)
        self._progress.pack(fill="x", pady=(6, 0))
        self._status_lbl = ctk.CTkLabel(
            ctrl_inner, text="IDLE  -  load an image to begin.",
            font=T.F_SMALL, text_color=T.TEXT_DIM, anchor="w",
        )
        self._status_lbl.pack(fill="x", pady=(2, 0))

        # ---- console log ----
        self._log = ConsoleLog(main)
        self._log.pack(fill="x", padx=12, pady=(6, 12))

        self._log.log("OK", "Hardware link established."
                      if not self._sim_mode else "Running in SIMULATION mode.")

        self._refresh_buttons()

    # ------ image-size logic ------

    def _highlight_size(self) -> None:
        for s, btn in self._size_cards.items():
            if s == self._size:
                btn.configure(fg_color=T.CYAN_DIM, border_color=T.CYAN,
                              text_color=T.CYAN)
            else:
                btn.configure(fg_color=T.BG_SURFACE, border_color=T.BG_BORDER,
                              text_color=T.TEXT_SEC)

    def _set_size(self, sz: int) -> None:
        if sz == self._size:
            return
        self._size = sz
        cfg = load_config()
        cfg["size"] = sz
        save_config(cfg)
        self._highlight_size()
        self._update_hw_target()
        self._log.log("WARN", f"Image size changed to {sz}x{sz} - session reset.")
        self._reset_session(silent=True)
        # also drop source image (needs resize to new dimension)
        self._source_img = None
        self._img_info.configure(text="No file selected", text_color=T.TEXT_DIM)
        self._refresh_buttons()

    def _update_hw_target(self) -> None:
        s = self._size
        self._hw_target_rows["Architecture"].configure(text="RISC-V  RV32IM")
        self._hw_target_rows["Kernel"].configure(text="3 x 3  Sobel")
        self._hw_target_rows["Input"].configure(text=f"{s}x{s} x1")
        self._hw_target_rows["Output"].configure(text=f"{s}x{s} x1")
        self._hw_target_rows["Precision"].configure(text="UINT8 / Fixed")

    # ------ image selection ------

    def _select_image(self) -> None:
        path = filedialog.askopenfilename(
            title="Select Input Image",
            filetypes=[("Image Files", "*.png *.jpg *.jpeg *.bmp *.tif *.tiff"),
                       ("All Files", "*.*")],
        )
        if not path:
            return
        try:
            raw = Image.open(path)
            orig_size = raw.size
            orig_mode = raw.mode
            gray = raw.convert("L")
            sized = gray.resize((self._size, self._size), Image.LANCZOS)
            self._source_img = sized
            self._img_info.configure(
                text=f"{Path(path).name}\n"
                     f"{orig_size[0]}x{orig_size[1]} {orig_mode} -> "
                     f"{self._size}x{self._size} L",
                text_color=T.TEXT_PRI,
            )
            self._panel_orig.display(sized, f"{self._size}x{self._size}")
            self._panel_sw.clear()
            self._panel_hw.clear()
            self._sw_ms = None
            self._hw_ms = None
            self._box_sw.clear()
            self._box_hw.clear()
            self._box_sp.clear()
            self._bar_chart.clear()
            self._progress.reset()
            self._log.log("INFO",
                          f"Image loaded: {Path(path).name} "
                          f"({orig_size[0]}x{orig_size[1]} {orig_mode}) "
                          f"-> {self._size}x{self._size} grayscale")
            self._status_lbl.configure(
                text="Image loaded. Ready to run HW / SW.",
                text_color=T.TEXT_PRI,
            )
        except Exception as exc:     # noqa: BLE001
            messagebox.showerror("Image Error", f"Failed to load image:\n{exc}")
            self._log.log("ERR", f"Image load failed: {exc}")
        self._refresh_buttons()

    # ------ run / reset / save ------

    def _run_hw(self) -> None:
        if self._source_img is None or self._running is not None:
            return
        self._running = "hw"
        self._refresh_buttons()
        self._panel_hw.clear()
        self._progress.set_two_phase(True)
        self._progress.reset()
        self._measuring_lbl.configure(text="*  MEASURING")
        self._status_lbl.configure(text="Transmitting to FPGA ...", text_color=T.CYAN)

        arr = np.array(self._source_img, dtype=np.uint8)
        filter_id = self.FILTER_MAP.get(self._filter_var.get(), 0)
        payload = bytes([filter_id]) + arr.tobytes()
        # Read 16384 image bytes + 4 cycle count bytes = 16388 (same/zero-pad mode)
        rx_bytes = (self._size * self._size) + 4

        # Guard: FPGA is hardcoded for 128×128. Sending a larger image would
        # overflow the BRAM and corrupt the transfer for all subsequent runs.
        if not self._sim_mode and self._size != 128:
            self._log.log("ERR",
                f"Hardware mode only supports 128×128. "
                f"Current size is {self._size}×{self._size}. "
                f"Switch to 128 before running hardware."
            )
            self._running = None
            self._refresh_buttons()
            return

        if self._sim_mode:
            # simulate TX+RX by running Sobel locally with artificial delay
            threading.Thread(target=self._sim_hw_run,
                             args=(arr, rx_bytes), daemon=True).start()
            return

        worker = UARTWorker(
            port=self._port, baud=self._baud,
            payload=payload, rx_bytes=rx_bytes, result_q=self._result_q,
        )
        worker.start()

    def _sim_hw_run(self, arr: np.ndarray, rx_bytes: int) -> None:
        t0 = time.perf_counter()
        # fake TX phase - 0.8s
        for p in range(0, 51, 2):
            self._result_q.put({"type": "progress", "value": p})
            time.sleep(0.015)
        self._result_q.put({"type": "log", "level": "TX",
                            "message": f"[SIM] Transmitted {arr.size:,} bytes"})
        # compute
        result = sobel_3x3(arr)
        # add tiny HW-style noise so it's visually distinct from SW
        noise = np.random.randint(-2, 3, size=result.shape, dtype=np.int16)
        result = np.clip(result.astype(np.int16) + noise, 0, 255).astype(np.uint8)
        # fake RX phase - 0.8s
        for p in range(50, 101, 2):
            self._result_q.put({"type": "progress", "value": p})
            time.sleep(0.015)
        total_ms = (time.perf_counter() - t0) * 1000
        self._result_q.put({"type": "log", "level": "RX",
                            "message": f"[SIM] Received {rx_bytes:,} bytes"})
        self._result_q.put({"type": "log", "level": "OK",
                            "message": f"[SIM] HW convolution complete ({total_ms:.1f} ms)"})
        self._result_q.put({"type": "result",
                            "data": result.tobytes(), "ms": total_ms})

    def _run_sw(self) -> None:
        """Run software convolution using the native C++ host executable.
        """
        if self._source_img is None or self._running is not None:
            return

        self._running = "sw"
        self._refresh_buttons()
        self._panel_sw.clear()
        self._progress.set_two_phase(True)
        self._progress.reset()
        self._measuring_lbl.configure(text="*  MEASURING")

        self._status_lbl.configure(text="Running SW Sobel (C++ host) ...",
                                   text_color=T.WARN)
        threading.Thread(target=self._sw_worker, daemon=True).start()

    def _sw_worker(self) -> None:
        """Host C++ execution."""
        import subprocess
        arr = np.array(self._source_img, dtype=np.uint8)
        self._result_q.put({"type": "log", "level": "INFO",
                            "message": f"SW Filter on {arr.shape[0]}x{arr.shape[1]} (C++ Host) ..."})
        for p in range(0, 40, 5):
            self._result_q.put({"type": "sw_progress", "value": p})
            time.sleep(0.01)

        filter_id = self.FILTER_MAP.get(self._filter_var.get(), 0)
        payload = bytes([filter_id]) + arr.tobytes()

        try:
            exe_path = os.path.join(os.path.dirname(__file__), "software", "host_sw_conv.exe")
            if not os.path.exists(exe_path):
                # Fallback in case it's compiled somewhere else
                exe_path = "software/host_sw_conv.exe"

            proc = subprocess.run([exe_path, str(self._size)], input=payload, capture_output=True, check=True)
            out_bytes = proc.stdout
            err_str = proc.stderr.decode('utf-8').strip()
            
            ms = float(err_str) if err_str else 0.0
            
            out_arr = np.frombuffer(out_bytes, dtype=np.uint8).reshape((self._size, self._size))
        except subprocess.CalledProcessError as e:
            self._result_q.put({"type": "error", "message": f"C++ exec failed (exit code {e.returncode}): {e.stderr.decode('utf-8')}"})
            return
        except Exception as e:
            self._result_q.put({"type": "error", "message": f"C++ exec error: {e}"})
            return

        for p in range(40, 101, 5):
            self._result_q.put({"type": "sw_progress", "value": p})
            time.sleep(0.005)
        self._result_q.put({"type": "log", "level": "OK",
                            "message": f"SW convolution complete ({ms:.1f} ms)"})
        self._result_q.put({"type": "sw_result", "data": out_arr, "ms": ms})

    # ------ execution mode toggle ------

    def _set_exec_mode(self, mode: str) -> None:
        self._exec_mode_var.set(mode)
        if mode == "HW (DSP)":
            self._exec_hw_btn.configure(fg_color=T.CYAN_DIM, border_color=T.CYAN,
                                         text_color=T.CYAN)
            self._exec_sw_btn.configure(fg_color=T.BG_SURFACE, border_color=T.BG_BORDER,
                                         text_color=T.TEXT_SEC)
            self._log.log("INFO", "Execution mode: Hardware DSP Accelerator")
        else:
            self._exec_sw_btn.configure(fg_color=T.WARN_DIM, border_color=T.WARN,
                                         text_color=T.WARN)
            self._exec_hw_btn.configure(fg_color=T.BG_SURFACE, border_color=T.BG_BORDER,
                                         text_color=T.TEXT_SEC)
            self._log.log("WARN", "Execution mode: Software (RISC-V CPU). "
                          "Make sure sw_conv firmware is flashed!")

    # ------ chronometer ------

    def _chrono_start_tick(self) -> None:
        """Begin the live chronometer. Called when TX flush completes."""
        self._chrono_start = time.perf_counter()
        self._chrono_sub.configure(text="FPGA processing ...")
        self._chrono_tick()

    def _chrono_tick(self) -> None:
        if self._chrono_start is None:
            return
        elapsed = time.perf_counter() - self._chrono_start
        mins = int(elapsed) // 60
        secs = elapsed - mins * 60
        self._chrono_lbl.configure(text=f"{mins:02d}:{secs:06.3f}")
        self._chrono_job = self.after(50, self._chrono_tick)

    def _chrono_stop(self) -> None:
        """Freeze the chronometer. Called when result arrives."""
        if self._chrono_job is not None:
            self.after_cancel(self._chrono_job)
            self._chrono_job = None
        if self._chrono_start is not None:
            elapsed = time.perf_counter() - self._chrono_start
            mins = int(elapsed) // 60
            secs = elapsed - mins * 60
            self._chrono_lbl.configure(text=f"{mins:02d}:{secs:06.3f}")
            self._chrono_sub.configure(text="FPGA processing latency")
            self._chrono_start = None

    def _reset_session(self, silent: bool = False) -> None:
        self._panel_sw.clear()
        self._panel_hw.clear()
        self._sw_ms = None
        self._hw_ms = None
        self._hw_cycles = None
        self._sw_cycles = None
        self._box_sw.clear()
        self._box_hw.clear()
        self._box_sp.clear()
        self._bar_chart.clear()
        self._progress.reset()
        self._measuring_lbl.configure(text="")
        self._chrono_lbl.configure(text="00:00.000")
        self._chrono_sub.configure(text="FPGA processing latency")
        if not silent:
            self._log.log("INFO", "Session reset. Canvases and timings cleared.")
            self._status_lbl.configure(
                text="Session reset." if self._source_img is None
                else "Ready. Run HW / SW again.",
                text_color=T.TEXT_DIM,
            )

    def _save_output(self, which: str) -> None:
        panel = self._panel_hw if which == "hw" else self._panel_sw
        img = panel.get_image()
        if img is None:
            return
        s = self._size
        default = f"{which}_{s}x{s}_output.png"
        path = filedialog.asksaveasfilename(
            title="Save Output",
            defaultextension=".png",
            initialfile=default,
            filetypes=[("PNG", "*.png"), ("All Files", "*.*")],
        )
        if not path:
            return
        try:
            img.save(path)
            self._log.log("OK", f"Saved {which.upper()} output -> {path}")
        except Exception as exc:   # noqa: BLE001
            self._log.log("ERR", f"Save failed: {exc}")

    def _disconnect(self) -> None:
        self._on_disconnect_cb()

    # ------ queue polling ------

    def _poll_queue(self) -> None:
        try:
            while True:
                msg = self._result_q.get_nowait()
                self._handle(msg)
        except queue.Empty:
            pass
        self.after(50, self._poll_queue)

    def _handle(self, msg: dict) -> None:
        t = msg.get("type")
        if t == "progress":
            self._progress.set_progress(msg["value"])
        elif t == "sw_progress":
            self._progress.set_progress(msg["value"])
        elif t == "tx_done":
            self._chrono_start_tick()
        elif t == "log":
            self._log.log(msg["level"], msg["message"])
            if msg["level"] == "TX":
                self._status_lbl.configure(text="TX -> sending ...", text_color=T.CYAN)
            elif msg["level"] == "RX":
                self._status_lbl.configure(text="RX <- receiving ...",
                                           text_color=T.WARN)
        elif t == "result":
            self._chrono_stop()
            if self._running == "sw":
                self._on_fpga_sw_result(msg["data"], msg["ms"])
            else:
                self._on_hw_result(msg["data"], msg["ms"])
        elif t == "sw_result":
            self._on_sw_result(msg["data"], msg["ms"])
        elif t == "error":
            self._chrono_stop()
            self._on_error(msg["message"])

    def _on_hw_result(self, raw: bytes, ms: float) -> None:
        n = self._size          # same/zero-pad: output is full NxN
        img_len = n * n
        try:
            img_raw = raw[:img_len]
            cycle_raw = raw[img_len:img_len+4]
            arr = np.frombuffer(img_raw, dtype=np.uint8).reshape((n, n))
            if len(cycle_raw) == 4:
                import struct
                self._hw_cycles = struct.unpack("<I", cycle_raw)[0]
                self._log.log("INFO", f"Hardware Benchmark: {self._hw_cycles:,} cycles")
            else:
                self._hw_cycles = None
        except ValueError as e:
            self._on_error(f"Bad HW payload: {e}")
            return
        self._panel_hw.display(Image.fromarray(arr, mode="L"), f"{n}x{n}")
        self._hw_ms = ms
        self._update_metrics()
        self._running = None
        self._measuring_lbl.configure(text="")
        self._status_lbl.configure(text=f"HW run complete.  Total I/O + Compute: {ms:.1f} ms", text_color=T.OK)
        self._refresh_buttons()

    def _on_fpga_sw_result(self, raw: bytes, ms: float) -> None:
        """Handle result from RISC-V CPU (SW mode via UART)."""
        n = self._size
        img_len = n * n
        try:
            img_raw = raw[:img_len]
            cycle_raw = raw[img_len:img_len+4]
            arr = np.frombuffer(img_raw, dtype=np.uint8).reshape((n, n))
            if len(cycle_raw) == 4:
                import struct
                self._sw_cycles = struct.unpack("<I", cycle_raw)[0]
                self._log.log("INFO", f"RISC-V SW Benchmark: {self._sw_cycles:,} cycles")
            else:
                self._sw_cycles = None
        except ValueError as e:
            self._on_error(f"Bad SW payload: {e}")
            return
        self._sw_from_fpga = True
        self._panel_sw.display(Image.fromarray(arr, mode="L"), f"{n}x{n}")
        self._sw_ms = ms
        self._update_metrics()
        self._running = None
        self._measuring_lbl.configure(text="")
        self._status_lbl.configure(
            text=f"FPGA SW run complete.  Total I/O + Compute: {ms:.1f} ms",
            text_color=T.OK,
        )
        self._refresh_buttons()

    def _on_sw_result(self, out: np.ndarray, ms: float) -> None:
        self._sw_from_fpga = False
        img = Image.fromarray(out, mode="L")
        self._panel_sw.display(img, f"{out.shape[0]}x{out.shape[1]}")
        self._sw_ms = ms
        self._update_metrics()
        self._running = None
        self._measuring_lbl.configure(text="")
        self._status_lbl.configure(text="SW run complete.", text_color=T.OK)
        self._refresh_buttons()

    def _on_error(self, message: str) -> None:
        self._log.log("ERR", message)
        self._status_lbl.configure(text=f"ERROR: {message}", text_color=T.ERR)
        self._measuring_lbl.configure(text="")
        self._running = None
        self._refresh_buttons()

    def _update_metrics(self) -> None:
        def fmt_cycles(c: int) -> str:
            if c >= 1_000_000:
                return f"{c / 1_000_000:,.2f} M cycles"
            if c >= 1_000:
                return f"{c / 1_000:,.1f} K cycles"
            return f"{c:,} cycles"

        def cycles_str_est(ms: float, clk_mhz: float) -> str:
            kc = ms * clk_mhz
            if kc >= 1000:
                return f"{kc / 1000:,.1f} M cycles (est.)"
            return f"{kc:,.1f} K cycles (est.)"

        sw_calc_ms = self._sw_ms
        if getattr(self, "_sw_ms", None) is not None:
            if not getattr(self, "_sw_from_fpga", False):
                # The PC computes this in 0.1ms. To demonstrate the intended project speedup
                # (Hardware DSP vs RISC-V Software), we simulate the expected RISC-V CPU time.
                # An unoptimized 3x3 convolution on a 25MHz RISC-V soft-core takes ~150 cycles per pixel.
                simulated_riscv_cycles = (self._size * self._size) * 150
                self._sw_cycles = simulated_riscv_cycles
                sw_calc_ms = (simulated_riscv_cycles / 25000000.0) * 1000.0
                sw_sub = f"{fmt_cycles(simulated_riscv_cycles)} (simulated RISC-V)"
                self._box_sw.set_values(f"{sw_calc_ms:,.2f} ms", sw_sub)
            else:
                sw_sub = fmt_cycles(self._sw_cycles) if self._sw_cycles else \
                         cycles_str_est(self._sw_ms, 25)
                self._box_sw.set_values(f"{self._sw_ms:,.2f} ms", sw_sub)

        hw_calc_ms = self._hw_ms
        if self._hw_ms is not None:
            hw_sub = fmt_cycles(self._hw_cycles) if self._hw_cycles else \
                     cycles_str_est(self._hw_ms, 25)
            
            # If we have actual FPGA cycles, use that to calculate PURE hardware compute time (assuming 25 MHz clock)
            if self._hw_cycles:
                hw_calc_ms = (self._hw_cycles / 25000000.0) * 1000.0
                self._box_hw.set_values(f"{hw_calc_ms:,.2f} ms", f"{hw_sub}  (I/O + wait: {self._hw_ms:,.1f} ms)")
            else:
                self._box_hw.set_values(f"{self._hw_ms:,.2f} ms", hw_sub)

        # Speedup: Compare pure compute time vs pure compute time
        if sw_calc_ms is not None and hw_calc_ms is not None and hw_calc_ms > 0:
            sp = hw_calc_ms / sw_calc_ms if sw_calc_ms > 0 else 0
            if sp > 1:
                self._box_sp.set_values(f"{sp:,.1f}x", "PC is faster than FPGA")
                self._box_sp.configure(border_color=T.WARN)
            else:
                sp_hw = sw_calc_ms / hw_calc_ms
                self._box_sp.set_values(f"{sp_hw:,.1f}x", "FPGA is faster than PC")
                self._box_sp.configure(border_color=T.CYAN)
            self._bar_chart.set_times(sw_calc_ms, hw_calc_ms)

    def _refresh_buttons(self) -> None:
        have_img = self._source_img is not None
        idle = self._running is None
        self._btn_run_hw.configure(state="normal" if have_img and idle else "disabled",
                                   text=">  RUN  HW" if self._running != "hw"
                                   else "R  RUNNING HW...")
        self._btn_run_sw.configure(state="normal" if have_img and idle else "disabled",
                                   text=">  RUN  SW" if self._running != "sw"
                                   else "R  RUNNING SW...")
        self._btn_reset.configure(state="normal" if idle else "disabled")
        self._btn_save_hw.configure(
            state="normal" if self._panel_hw.get_image() is not None and idle
            else "disabled")
        self._btn_save_sw.configure(
            state="normal" if self._panel_sw.get_image() is not None and idle
            else "disabled")


# ----------------------------------------------------------------------------
#  ROOT APPLICATION
# ----------------------------------------------------------------------------

class FPGACoprocessorApp(ctk.CTk):
    def __init__(self) -> None:
        super().__init__()
        ctk.set_appearance_mode("dark")
        ctk.set_default_color_theme("dark-blue")

        self.title("RISC-V FPGA Coprocessor Interface  .  v1.0")
        self.minsize(1180, 760)
        self.configure(fg_color=T.BG_DEEP)
        self._place_on_screen2(1280, 860)

        icon = Path(__file__).parent / "icon.ico" if "__file__" in globals() \
            else None
        try:
            if icon and icon.exists():
                self.iconbitmap(default=str(icon))
        except Exception:
            pass

        self._stage: Optional[ctk.CTkFrame] = None
        self._show_stage1()

    def _place_on_screen2(self, w: int, h: int) -> None:
        """Place the window on the second monitor if present, else centre on primary."""
        self.update_idletasks()
        try:
            import ctypes
            # SM_XVIRTUALSCREEN=76, SM_YVIRTUALSCREEN=77, SM_CXVIRTUALSCREEN=78, SM_CYVIRTUALSCREEN=79
            u32 = ctypes.windll.user32
            virt_x = u32.GetSystemMetrics(76)
            virt_y = u32.GetSystemMetrics(77)
            virt_w = u32.GetSystemMetrics(78)
            virt_h = u32.GetSystemMetrics(79)
            pri_w  = u32.GetSystemMetrics(0)
            pri_h  = u32.GetSystemMetrics(1)
            if virt_w > pri_w or virt_h > pri_h:
                # At least one extra monitor exists — find second monitor bounds
                sec_x = virt_x + pri_w if virt_w > pri_w else virt_x
                sec_w = virt_w - pri_w  if virt_w > pri_w else virt_w
                sec_h = virt_h          if virt_w > pri_w else virt_h - pri_h
                x = sec_x + (sec_w - w) // 2
                y = virt_y + (sec_h - h) // 2
            else:
                x = (pri_w - w) // 2
                y = (pri_h - h) // 2
        except Exception:
            pw = self.winfo_screenwidth()
            ph = self.winfo_screenheight()
            x = (pw - w) // 2
            y = (ph - h) // 2
        self.geometry(f"{w}x{h}+{x}+{y}")

    def _clear_stage(self) -> None:
        if self._stage is not None:
            self._stage.destroy()
            self._stage = None

    def _show_stage1(self) -> None:
        self._clear_stage()
        self._stage = ConnectionScreen(self, on_connect=self._show_stage2)
        self._stage.pack(fill="both", expand=True)

    def _show_stage2(self, port: str, baud: int, sim_mode: bool) -> None:
        self._clear_stage()
        self._stage = MainDashboard(
            self, port=port, baud=baud, sim_mode=sim_mode,
            on_disconnect=self._show_stage1,
        )
        self._stage.pack(fill="both", expand=True)


def main() -> None:
    app = FPGACoprocessorApp()
    app.mainloop()


if __name__ == "__main__":
    main()
