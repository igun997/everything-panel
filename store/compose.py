#!/usr/bin/env python3
"""Turns the raw screenshots (build/store_shots) into captioned Play Store images.

Needs ImageMagick (`convert`) and the DM Sans TTFs (FONT_BOLD / FONT_MEDIUM environment
variables, defaulting to build/fonts/dmsans-700.ttf and dmsans-500.ttf, the files the
store-screenshots workflow downloads).

    python3 store/compose.py build/store_shots store/screenshots
"""
import os
import subprocess
import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "build/store_shots"
OUT = sys.argv[2] if len(sys.argv) > 2 else "store/screenshots"
BOLD = os.environ.get("FONT_BOLD", "build/fonts/dmsans-700.ttf")
MEDIUM = os.environ.get("FONT_MEDIUM", "build/fonts/dmsans-500.ttf")

CAPTIONS = {
    "01-welcome": ("Every server.\nOne glass panel.", "Control your hosting panels from your pocket"),
    "02-fleet": ("All your servers\nat a glance", "Live health across every panel you run"),
    "03-services": ("Find any service\nin seconds", "Grouped by project, with search that stays put"),
    "04-service": ("Start, stop,\nrestart, deploy", "Asks first before anything disruptive"),
    "05-activity": ("Builds and deploys,\nall logged", "Read exactly what happened"),
    "06-system": ("CPU, memory, disk\nand uptime", "Know your host is healthy"),
}

# set -> (canvas WxH, raw WxH, screenshot width, caption size, subtitle size, caption y, shot y)
LAYOUT = {
    "phone": ((1080, 1920), (1080, 1920), 820, 72, 38, 96, 380),
    "tablet7": ((1200, 1920), (1200, 1920), 940, 78, 40, 96, 400),
    "tablet10": ((2560, 1600), (2560, 1600), 1900, 92, 46, 70, 330),
}


def run(*args):
    subprocess.run(args, check=True)


for name, ((w, h), (rw, rh), shot_w, cap_size, sub_size, cap_y, shot_y) in LAYOUT.items():
    out_dir = os.path.join(OUT, name)
    os.makedirs(out_dir, exist_ok=True)
    shot_h = round(shot_w * rh / rw)
    radius = 56 if name != "tablet10" else 40
    for key, (title, sub) in CAPTIONS.items():
        raw = os.path.join(SRC, name, key + ".png")
        if not os.path.exists(raw):
            print("skip (no raw):", raw)
            continue
        dst = os.path.join(out_dir, key + ".png")
        mask = dst + ".mask.png"
        shot = dst + ".shot.png"

        # Rounded screenshot: a white rounded rectangle becomes its alpha channel.
        run("convert", "-size", f"{shot_w}x{shot_h}", "xc:black", "-fill", "white",
            "-draw", f"roundrectangle 0,0 {shot_w - 1},{shot_h - 1} {radius},{radius}", mask)
        run("convert", raw, "-resize", f"{shot_w}x{shot_h}!", mask,
            "-alpha", "off", "-compose", "CopyOpacity", "-composite", shot)

        # Canvas: near-black with a mint and a sage glow, the caption, then the shot with a shadow.
        mint = (int(w * 0.85), int(h * 0.12))
        sage = (int(w * 0.05), int(h * 0.62))
        run(
            "convert", "-size", f"{w}x{h}", "xc:#0A0A0A",
            "(", "-size", f"{w}x{h}", "xc:none",
            "-fill", "rgba(89,242,189,0.20)", "-draw", f"circle {mint[0]},{mint[1]} {mint[0] + int(w * 0.35)},{mint[1]}",
            "-fill", "rgba(149,171,167,0.16)", "-draw", f"circle {sage[0]},{sage[1]} {sage[0] + int(w * 0.4)},{sage[1]}",
            "-blur", "0x140", ")", "-compose", "Over", "-composite",
            "-gravity", "North", "-font", BOLD, "-pointsize", str(cap_size), "-fill", "#F4F6F5",
            "-interline-spacing", "-6", "-annotate", f"+0+{cap_y}", title,
            "-font", MEDIUM, "-pointsize", str(sub_size), "-fill", "#95ABA7",
            "-annotate", f"+0+{cap_y + cap_size * 2 + 38}", sub,
            "(", shot, "(", "+clone", "-background", "black", "-shadow", "60x30+0+22", ")", "+swap",
            "-background", "none", "-layers", "merge", "+repage", ")",
            "-gravity", "North", "-compose", "Over", "-geometry", f"+0+{shot_y - 30}", "-composite",
            "-depth", "8", dst,
        )
        os.remove(mask)
        os.remove(shot)
        print("wrote", dst)
