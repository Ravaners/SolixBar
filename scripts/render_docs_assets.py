#!/usr/bin/env python3
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "docs" / "assets"
ICON = ROOT / "Assets" / "SolixBar.png"

INK = (23, 33, 29)
MUTED = (91, 105, 98)
PAPER = (251, 252, 249)
PANEL = (255, 255, 255)
LINE = (217, 226, 220)
GREEN = (44, 143, 99)
GREEN_BRIGHT = (28, 190, 93)
SOLAR = (228, 167, 47)
BLUE = (45, 113, 214)
RED = (214, 76, 69)
PURPLE = (116, 96, 214)
SOFT_GREEN = (228, 246, 236)
SOFT_SOLAR = (255, 244, 216)
SOFT_BLUE = (230, 240, 255)
SOFT_RED = (252, 232, 230)
SOFT_PURPLE = (238, 234, 255)


def font(size: int, weight: str = "regular") -> ImageFont.FreeTypeFont:
    candidates = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if weight in {"bold", "black"} else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/Library/Fonts/Arial.ttf",
    ]
    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size=size)
        except OSError:
            continue
    return ImageFont.load_default()


F = {
    "tiny": font(24),
    "small": font(30),
    "body": font(36),
    "body_bold": font(36, "bold"),
    "h3": font(44, "bold"),
    "h2": font(62, "bold"),
    "hero": font(92, "bold"),
    "metric": font(66, "bold"),
    "menu": font(38, "bold"),
}


def rounded(draw: ImageDraw.ImageDraw, box, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def shadow(base: Image.Image, box, radius=34, blur=28, offset=(0, 18), alpha=42):
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    shifted = (box[0] + offset[0], box[1] + offset[1], box[2] + offset[0], box[3] + offset[1])
    d.rounded_rectangle(shifted, radius=radius, fill=(20, 28, 24, alpha))
    base.alpha_composite(layer.filter(ImageFilter.GaussianBlur(blur)))


def text(draw, xy, value, fill=INK, f=None, anchor=None):
    draw.text(xy, value, fill=fill, font=f or F["body"], anchor=anchor)


def paste_icon(base: Image.Image, box):
    icon = Image.open(ICON).convert("RGBA")
    size = int(min(box[2] - box[0], box[3] - box[1]))
    icon = icon.resize((size, size), Image.Resampling.LANCZOS)
    base.alpha_composite(icon, (int(box[0]), int(box[1])))


def gradient(size, colors):
    w, h = size
    img = Image.new("RGBA", size, colors[0])
    pix = img.load()
    for y in range(h):
        for x in range(w):
            t = (x / max(1, w - 1) + y / max(1, h - 1)) / 2
            if t < 0.5:
                a, b = colors[0], colors[1]
                f = t / 0.5
            else:
                a, b = colors[1], colors[2]
                f = (t - 0.5) / 0.5
            pix[x, y] = tuple(int(a[i] + (b[i] - a[i]) * f) for i in range(4))
    return img


def menu_bar(base, x, y, w, h, dark=False):
    draw = ImageDraw.Draw(base)
    fill = (22, 29, 25) if dark else (241, 246, 241)
    rounded(draw, (x, y, x + w, y + h), 24, fill)
    compact = w < 1100
    if dark:
        text(draw, (x + 110, y + 50), "Akku 88%", (107, 255, 148), F["menu"])
        text(draw, (x + (300 if compact else 350), y + 50), "↓ 144 W" if compact else "↓ Laden 144 W", (107, 255, 148), F["menu"])
        text(draw, (x + (500 if compact else 735), y + 50), "PV 496 W", (255, 209, 77), F["menu"])
        text(draw, (x + (680 if compact else 980), y + 50), "Netz → 86 W" if compact else "Netz → Einspeisen 86 W", (209, 166, 255), F["menu"])
    else:
        text(draw, (x + 110, y + 50), "Akku 88%", (0, 92, 31), F["menu"])
        text(draw, (x + (300 if compact else 350), y + 50), "↓ 144 W" if compact else "↓ Laden 144 W", (0, 92, 31), F["menu"])
        text(draw, (x + (500 if compact else 735), y + 50), "PV 496 W", (122, 56, 0), F["menu"])
        text(draw, (x + (680 if compact else 980), y + 50), "Netz → 86 W" if compact else "Netz → Einspeisen 86 W", (87, 25, 148), F["menu"])
    paste_icon(base, (x + 28, y + 14, x + 78, y + 64))


def dashboard(base, x, y, scale=1.0):
    d = ImageDraw.Draw(base)
    w, h = int(820 * scale), int(1060 * scale)
    shadow(base, (x, y, x + w, y + h), radius=int(36 * scale))
    rounded(d, (x, y, x + w, y + h), int(36 * scale), (248, 251, 249), (124, 136, 130), 3)
    text(d, (x + 58, y + 86), "Anker SOLIX", INK, F["h2"])
    rounded(d, (x + w - 184, y + 58, x + w - 48, y + 116), 29, (226, 248, 232), (107, 211, 125), 3)
    text(d, (x + w - 116, y + 75), "Online", INK, F["body_bold"], anchor="ma")
    text(d, (x + 58, y + 142), "Aktualisiert gerade eben", MUTED, F["body_bold"])
    metric_card(base, x + 58, y + 214, 340, 165, "Akku", "88 %", "▱", GREEN, SOFT_GREEN)
    metric_card(base, x + 430, y + 214, 332, 165, "Solar", "496 W", "☀", SOLAR, SOFT_SOLAR)
    rows = [
        ("⌂", "Hauslast", "352 W", BLUE, SOFT_BLUE),
        ("▣", "Netzbezug", "-86 W", (51, 150, 170), (224, 241, 244)),
        ("ϟ", "Akku-Fluss", "+144 W", GREEN_BRIGHT, SOFT_GREEN),
        ("▮", "Heutiger Ertrag", "7.42 kWh", PURPLE, SOFT_PURPLE),
        ("Σ", "Gesamtertrag", "427.8 kWh", (94, 94, 210), (232, 232, 250)),
    ]
    row_y = y + 430
    for icon, label, value, color, fill in rows:
        rounded(d, (x + 58, row_y, x + 762, row_y + 74), 20, fill)
        text(d, (x + 92, row_y + 20), icon, color, F["body_bold"])
        text(d, (x + 148, row_y + 20), label, INK, F["body_bold"])
        text(d, (x + 736, row_y + 20), value, INK, F["body_bold"], anchor="ra")
        row_y += 86
    mini_graph(base, x + 58, y + 890, 704, 130, compact=True)


def metric_card(base, x, y, w, h, label, value, icon, color, fill):
    d = ImageDraw.Draw(base)
    rounded(d, (x, y, x + w, y + h), 28, fill, (130, 148, 139), 3)
    text(d, (x + 42, y + 35), icon, color, F["h3"])
    text(d, (x + 112, y + 42), label, INK, F["h3"])
    text(d, (x + 112, y + 104), value, INK, F["metric"])


def mini_graph(base, x, y, w, h, compact=False):
    d = ImageDraw.Draw(base)
    rounded(d, (x, y, x + w, y + h), 24, PANEL, (128, 139, 134), 3)
    title_font = F["body_bold"] if not compact else F["small"]
    text(d, (x + 34, y + 24), "Verlauf 24 Stunden", INK, title_font)
    plot = (x + 78, y + 62, x + w - 58, y + h - 24)
    for i in range(4):
        yy = plot[1] + (plot[3] - plot[1]) * i / 3
        d.line((plot[0], yy, plot[2], yy), fill=(210, 220, 215), width=2)
    curve(d, plot, GREEN_BRIGHT, [0.66, 0.70, 0.72, 0.71, 0.74, 0.79, 0.86])
    curve(d, plot, SOLAR, [0.12, 0.28, 0.48, 0.56, 0.50, 0.32, 0.10])
    curve(d, plot, RED, [0.06, 0.04, 0.03, 0.04, 0.05, 0.08, 0.13])
    text(d, (plot[0], plot[3] + 8), "15:49", MUTED, F["tiny"])
    text(d, ((plot[0] + plot[2]) // 2, plot[3] + 8), "03:49", MUTED, F["tiny"], anchor="ma")
    text(d, (plot[2], plot[3] + 8), "Jetzt", MUTED, F["tiny"], anchor="ra")


def curve(d, plot, color, values):
    pts = []
    for i, v in enumerate(values):
        x = plot[0] + (plot[2] - plot[0]) * i / (len(values) - 1)
        y = plot[3] - (plot[3] - plot[1]) * v
        pts.append((x, y))
    d.line(pts, fill=color, width=7, joint="curve")
    d.ellipse((pts[-1][0] - 8, pts[-1][1] - 8, pts[-1][0] + 8, pts[-1][1] + 8), fill=PANEL, outline=color, width=5)


def render_preview():
    base = gradient((1600, 1100), [(248, 255, 249, 255), (240, 248, 244, 255), (232, 242, 255, 255)])
    d = ImageDraw.Draw(base)
    text(d, (90, 90), "SolixBar", INK, F["hero"])
    text(d, (96, 196), "Anker SOLIX direkt in der macOS-Menüleiste", MUTED, F["body_bold"])
    menu_bar(base, 520, 92, 940, 84)
    shadow(base, (120, 340, 470, 780), radius=34, blur=34)
    rounded(d, (120, 340, 470, 780), 34, PANEL, (128, 139, 134), 3)
    paste_icon(base, (190, 392, 400, 602))
    text(d, (295, 648), "SolixBar", INK, F["h3"], anchor="ma")
    text(d, (295, 704), "Hell, klar und aktuell", MUTED, F["small"], anchor="ma")
    large_graph(base, 560, 315, 900, 560)
    save(base, "solixbar-preview.png")


def render_menubar():
    base = gradient((1600, 840), [(251, 252, 249, 255), (239, 249, 242, 255), (232, 242, 255, 255)])
    d = ImageDraw.Draw(base)
    text(d, (90, 82), "Menüleisten-Anzeige", INK, F["h2"])
    text(d, (92, 154), "Kontrastreich, frei auswählbar und mit farbigen Energiefluss-Pfeilen.", MUTED, F["body"])
    shadow(base, (90, 260, 1510, 380), radius=34, blur=34)
    menu_bar(base, 90, 260, 1420, 120)
    shadow(base, (90, 430, 1510, 550), radius=34, blur=34)
    menu_bar(base, 90, 430, 1420, 120, dark=True)
    rounded(d, (90, 620, 770, 730), 24, (241, 246, 241))
    paste_icon(base, (120, 648, 172, 700))
    text(d, (205, 660), "↻ Aktualisiert ...", (0, 51, 204), F["menu"])
    rounded(d, (830, 620, 1510, 730), 24, (22, 29, 25))
    paste_icon(base, (860, 648, 912, 700))
    text(d, (945, 660), "↻ Aktualisiert ...", (102, 224, 255), F["menu"])
    text(d, (128, 775), "Akku 15%", (176, 0, 33), F["small"])
    text(d, (360, 775), "Akku 45%", (138, 89, 0), F["small"])
    text(d, (592, 775), "Akku 88%", (0, 92, 31), F["small"])
    text(d, (930, 775), "Hell und Dunkel · Light and dark", MUTED, F["small"])
    save(base, "menubar-shot.png")


def render_dashboard():
    base = gradient((1600, 1300), [(252, 255, 252, 255), (239, 248, 244, 255), (255, 245, 226, 255)])
    d = ImageDraw.Draw(base)
    text(d, (92, 82), "Dashboard", INK, F["h2"])
    text(d, (94, 154), "Alle wichtigen Werte beim Klick auf die Menüleiste.", MUTED, F["body"])
    dashboard(base, 420, 230, 1.0)
    save(base, "dashboard-shot.png")


def render_detached():
    base = gradient((1600, 760), [(248, 255, 249, 255), (237, 247, 243, 255), (255, 240, 227, 255)])
    d = ImageDraw.Draw(base)
    text(d, (90, 76), "Abgedockte Leiste", INK, F["h2"])
    text(d, (92, 148), "Fixiert ohne Schliesskreuz, entfixiert mit direkter Schliessmoeglichkeit.", MUTED, F["body"])
    detached_bar(base, d, 130, 275, locked=True)
    text(d, (130, 245), "Fixiert · Locked", MUTED, F["small"])
    detached_bar(base, d, 130, 500, locked=False)
    text(d, (130, 470), "Entfixiert · Unlocked", MUTED, F["small"])
    save(base, "detached-bar-shot.png")


def detached_bar(base, d, x, y, locked):
    right = 1420 if locked else 1470
    shadow(base, (x, y, right, y + 110), radius=36, blur=28)
    rounded(d, (x, y, right, y + 110), 36, (22, 29, 25), (130, 150, 140), 3)
    paste_icon(base, (x + 40, y + 29, x + 92, y + 81))
    text(d, (x + 120, y + 43), "Akku 88%", (125, 255, 153), F["menu"])
    text(d, (x + 325, y + 43), "↓", (125, 255, 153), F["menu"])
    d.ellipse((x + 380, y + 48, x + 404, y + 72), fill=(255, 217, 77))
    text(d, (x + 420, y + 43), "PV 496 W", (255, 217, 77), F["menu"])
    d.rounded_rectangle((x + 660, y + 48, x + 684, y + 72), radius=5, fill=(117, 219, 255))
    text(d, (x + 700, y + 43), "Hauslast 352 W", (117, 219, 255), F["menu"])
    d.ellipse((x + 1015, y + 48, x + 1039, y + 72), fill=(214, 176, 255))
    text(d, (x + 1055, y + 43), "Netz 86 W", (214, 176, 255), F["menu"])
    if not locked:
        text(d, (x + 1280, y + 38), "×", (255, 255, 255), F["h3"])


def render_graph():
    base = gradient((1600, 1050), [(252, 255, 252, 255), (239, 248, 246, 255), (244, 245, 255, 255)])
    d = ImageDraw.Draw(base)
    text(d, (90, 76), "Verlauf", INK, F["h2"])
    text(d, (92, 148), "Aktuell, 24 Stunden, 7 Tage, 30 Tage oder ein eigener Zeitraum.", MUTED, F["body"])
    large_graph(base, 120, 250, 1360, 650)
    save(base, "graph-shot.png")


def large_graph(base, x, y, w, h):
    d = ImageDraw.Draw(base)
    shadow(base, (x, y, x + w, y + h), radius=34, blur=34)
    rounded(d, (x, y, x + w, y + h), 30, (248, 251, 249), (128, 139, 134), 3)
    text(d, (x + 50, y + 50), "SOLIX Verlauf", INK, F["h3"])
    tabs = ["Akt.", "24h", "7T", "30T", "Eig."]
    tab_w = 72 if w < 900 else 92
    tab_gap = 10 if w < 900 else 12
    tx = x + w - (tab_w * len(tabs) + tab_gap * (len(tabs) - 1)) - 54
    for tab in tabs:
        fill = (210, 213, 210) if tab == "24h" else (238, 239, 237)
        rounded(d, (tx, y + 42, tx + tab_w, y + 86), 14, fill)
        text(d, (tx + tab_w / 2, y + 52), tab, INK, F["small"], anchor="ma")
        tx += tab_w + tab_gap
    for i, (label, color) in enumerate([("Akku", GREEN_BRIGHT), ("Solar", SOLAR), ("Netzbezug", RED)]):
        rounded(d, (x + 58 + i * 190, y + 120, x + 190 + i * 190, y + 166), 16, tuple(min(255, c + 205) for c in color)[:3] + (255,))
        text(d, (x + 82 + i * 190, y + 129), "● " + label, color, F["small"])
    plot = (x + 100, y + 220, x + w - 100, y + h - 105)
    rounded(d, (plot[0] - 16, plot[1] - 16, plot[2] + 16, plot[3] + 16), 22, PANEL, (154, 163, 158), 3)
    for i in range(5):
        yy = plot[1] + (plot[3] - plot[1]) * i / 4
        d.line((plot[0], yy, plot[2], yy), fill=(198, 207, 202), width=2)
        text(d, (plot[0] - 20, yy - 16), f"{100 - i * 25}%", MUTED, F["tiny"], anchor="ra")
        text(d, (plot[2] + 22, yy - 16), f"{2000 - i * 500}W", MUTED, F["tiny"])
    curve(d, plot, GREEN_BRIGHT, [0.66, 0.70, 0.72, 0.71, 0.74, 0.79, 0.86])
    curve(d, plot, SOLAR, [0.12, 0.28, 0.48, 0.56, 0.50, 0.32, 0.10])
    curve(d, plot, RED, [0.06, 0.04, 0.03, 0.04, 0.05, 0.08, 0.13])
    labels = ["15:49", "21:49", "03:49", "09:49", "Jetzt"]
    for i, label in enumerate(labels):
        xx = plot[0] + (plot[2] - plot[0]) * i / (len(labels) - 1)
        text(d, (xx, plot[3] + 30), label, MUTED, F["tiny"], anchor="ma")


def render_settings():
    base = gradient((1600, 1050), [(251, 252, 249, 255), (241, 247, 243, 255), (235, 243, 255, 255)])
    d = ImageDraw.Draw(base)
    text(d, (90, 76), "Einstellungen", INK, F["h2"])
    text(d, (92, 148), "Menueleiste und abgedockte Leiste unabhaengig und direkt sortierbar.", MUTED, F["body"])
    shadow(base, (360, 230, 1240, 900), radius=34, blur=34)
    rounded(d, (360, 230, 1240, 900), 28, PANEL, (160, 170, 164), 3)
    text(d, (410, 278), "SOLIX Bar 0.5.3", INK, F["h3"])
    tabs = ["Menueleiste", "Abgedockt", "Warnungen", "Datenquelle", "App", "Start"]
    xx = 405
    for index, label in enumerate(tabs):
        width = 126 if label != "Datenquelle" else 148
        fill = (225, 242, 232) if index == 0 else (244, 247, 245)
        rounded(d, (xx, 330, xx + width, 378), 12, fill, (202, 213, 207), 2)
        text(d, (xx + width / 2, 342), label, GREEN if index == 0 else MUTED, F["tiny"], anchor="ma")
        xx += width + 6
    text(d, (420, 408), "Werte und Reihenfolge", INK, F["body_bold"])
    rows = [
        (True, "Akku", "78%", GREEN_BRIGHT),
        (True, "PV", "640W", SOLAR),
        (True, "Hauslast", "420W", BLUE),
        (True, "Netzbezug", "80W", BLUE),
        (False, "Akku-Fluss", "220W", GREEN),
    ]
    yy = 452
    for enabled, title, value, color in rows:
        rounded(d, (420, yy, 1180, yy + 62), 14, (247, 250, 248), (225, 231, 228), 2)
        d.rectangle((446, yy + 19, 468, yy + 41), outline=GREEN if enabled else (150, 158, 154), width=3)
        if enabled:
            d.line((450, yy + 30, 457, yy + 37, 466, yy + 22), fill=GREEN, width=3)
        text(d, (490, yy + 13), title, INK, F["body_bold"])
        text(d, (825, yy + 13), value, color, F["body_bold"])
        rounded(d, (1084, yy + 10, 1122, yy + 50), 9, (237, 242, 239), (198, 207, 202), 2)
        rounded(d, (1130, yy + 10, 1168, yy + 50), 9, (237, 242, 239), (198, 207, 202), 2)
        text(d, (1103, yy + 13), "↑", MUTED, F["small"], anchor="ma")
        text(d, (1149, yy + 13), "↓", MUTED, F["small"], anchor="ma")
        text(d, (1182, yy + 13), "?", MUTED, F["small"], anchor="ma")
        yy += 68
    text(d, (420, 810), "Live-Vorschau", INK, F["body_bold"])
    rounded(d, (420, 848, 1180, 884), 10, (34, 40, 39), (74, 86, 81), 2)
    text(d, (444, 850), "Akku 78%   PV 640W   Last 420W   Netz 80W", (238, 245, 241), F["small"])
    save(base, "settings-shot.png")


def render_warnings():
    base = gradient((1600, 1050), [(251, 252, 249, 255), (244, 248, 245, 255), (255, 245, 229, 255)])
    d = ImageDraw.Draw(base)
    text(d, (90, 76), "Individuelle Warnungen", INK, F["h2"])
    text(d, (92, 148), "Schwelle und Mindestdauer fuer jeden Energiefluss getrennt festlegen.", MUTED, F["body"])
    shadow(base, (290, 225, 1310, 920), radius=34, blur=34)
    rounded(d, (290, 225, 1310, 920), 28, PANEL, (160, 170, 164), 3)
    text(d, (345, 275), "Warnungen", INK, F["h3"])
    headers = [("Aktiv", 350), ("Warnung", 455), ("Schwelle", 820), ("Dauer", 1040), ("Info", 1208)]
    for label, xx in headers:
        text(d, (xx, 340), label, MUTED, F["small"])
    rows = [
        (True, "Akku niedrig", "20 %", "1 Minute"),
        (True, "Solar-Einbruch", "60 %", "5 Minuten"),
        (False, "Hauslast hoch", "1500 W", "2 Minuten"),
        (True, "Netzbezug hoch", "1000 W", "3 Minuten"),
        (False, "Einspeisung hoch", "1000 W", "2 Minuten"),
        (False, "Akku-Ladung hoch", "1000 W", "2 Minuten"),
        (False, "Akku-Entladung hoch", "1000 W", "2 Minuten"),
    ]
    yy = 390
    for enabled, title, threshold, duration in rows:
        rounded(d, (335, yy, 1265, yy + 58), 13, (247, 250, 248), (226, 232, 228), 2)
        d.rectangle((357, yy + 18, 379, yy + 40), outline=GREEN if enabled else (150, 158, 154), width=3)
        if enabled:
            d.line((361, yy + 29, 368, yy + 36, 377, yy + 21), fill=GREEN, width=3)
        text(d, (455, yy + 13), title, INK if enabled else MUTED, F["body_bold"])
        text(d, (820, yy + 13), threshold, GREEN if enabled else MUTED, F["body_bold"])
        text(d, (1040, yy + 13), duration, INK if enabled else MUTED, F["body"])
        text(d, (1218, yy + 13), "?", MUTED, F["body_bold"], anchor="ma")
        yy += 64
    rounded(d, (335, 850, 1265, 892), 12, (237, 245, 240), (211, 224, 216), 2)
    text(d, (355, 858), "Solar: hoechster Wert der letzten 30 Minuten; unter 100 W keine Nachtwarnung.", MUTED, F["tiny"])
    save(base, "warnings-shot.png")


def render_flow():
    base = gradient((1600, 950), [(252, 255, 252, 255), (238, 248, 242, 255), (255, 244, 226, 255)])
    d = ImageDraw.Draw(base)
    text(d, (90, 76), "Energiefluss", INK, F["h2"])
    text(d, (92, 148), "Farben und Pfeile zeigen schnell, ob geladen, verbraucht oder eingespeist wird.", MUTED, F["body"])
    cx, cy = 800, 530
    paste_icon(base, (700, 390, 900, 590))
    nodes = [
        ("Solar", (420, 280), SOLAR, "496 W", "↓ lädt"),
        ("Akku", (420, 700), GREEN_BRIGHT, "88 %", "+144 W"),
        ("Hauslast", (1180, 280), BLUE, "352 W", "Verbrauch"),
        ("Netzbezug", (1180, 700), GREEN, "-86 W", "Einspeisung"),
    ]
    for label, (nx, ny), color, value, sub in nodes:
        d.line((cx, cy, nx, ny), fill=color, width=10)
        d.polygon(arrow_head(cx, cy, nx, ny, 32), fill=color)
        shadow(base, (nx - 150, ny - 82, nx + 150, ny + 82), radius=26, blur=20, alpha=30)
        rounded(d, (nx - 150, ny - 82, nx + 150, ny + 82), 26, PANEL, color, 3)
        text(d, (nx, ny - 45), label, INK, F["body_bold"], anchor="ma")
        text(d, (nx, ny - 4), value, color, F["h3"], anchor="ma")
        text(d, (nx, ny + 45), sub, MUTED, F["small"], anchor="ma")
    save(base, "flow-shot.png")


def arrow_head(x1, y1, x2, y2, size):
    angle = math.atan2(y2 - y1, x2 - x1)
    tip = (x2 - math.cos(angle) * 160, y2 - math.sin(angle) * 90)
    left = (tip[0] - math.cos(angle - 0.8) * size, tip[1] - math.sin(angle - 0.8) * size)
    right = (tip[0] - math.cos(angle + 0.8) * size, tip[1] - math.sin(angle + 0.8) * size)
    return [tip, left, right]


def legend(d, x, y):
    items = [("Akku", GREEN), ("Solar", SOLAR), ("Netzbezug", BLUE), ("Energiefluss", GREEN_BRIGHT), ("Ertrag", PURPLE)]
    for label, color in items:
        d.ellipse((x, y, x + 20, y + 20), fill=color)
        text(d, (x + 32, y - 8), label, MUTED, F["small"])
        x += 245


def save(img: Image.Image, name: str):
    ASSETS.mkdir(parents=True, exist_ok=True)
    img.save(ASSETS / name)


def main():
    render_preview()
    render_menubar()
    render_dashboard()
    render_detached()
    render_graph()
    render_settings()
    render_warnings()
    render_flow()


if __name__ == "__main__":
    main()
