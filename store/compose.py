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
    "01-welcome": ("Every server.\\nOne glass panel.", "Control your hosting panels from your pocket"),
    "02-fleet": ("All your servers\\nat a glance", "Live health across every panel you run"),
    "03-services": ("Find any service\\nin seconds", "Grouped by project, with search that stays put"),
    "04-service": ("Start, stop,\\nrestart, deploy", "Asks first before anything disruptive"),
    "05-activity": ("Builds and deploys,\\nall logged", "Read exactly what happened"),
    "06-system": ("CPU, memory, disk\\nand uptime", "Know your host is healthy"),
}

# set -> (canvas WxH, screenshot width, caption font size, subtitle size, caption y, shot y)
LAYOUT = {
    "phone": ((1080, 1920), 860, 72, 38, 96, 400),
    "tablet7": ((1200, 1920), 980, 78, 40, 96, 410),
    "tablet10": ((2560, 1600), 1900, 92, 46, 70, 330),
}


def run(*args):
    subprocess.run(args, check=True)


for name, ((w, h), shot_w, cap_size, sub_size, cap_y, shot_y) in LAYOUT.items():
    out_dir = os.path.join(OUT, name)
    os.makedirs(out_dir, exist_ok=True)
    for key, (title, sub) in CAPTIONS.items():
        raw = os.path.join(SRC, name, key + ".png")
        if not os.path.exists(raw):
            print("skip (no raw):", raw)
            continue
        shot_h = round(shot_w * (1600 / 2560 if name == "tablet10" else 1920 / (1080 if name == "phone" else 1200)))
        radius = 48 if name != "tablet10" else 36
        dst = os.path.join(out_dir, key + ".png")
        tmp = dst + ".tmp.png"
        # Rounded screenshot with a soft shadow.
        run(
            "convert", raw, "-resize", f"{shot_w}x{shot_h}!",
            "(", "+clone", "-alpha", "extract", "-draw",
            f"fill black polygon 0,0 0,{radius} {radius},0 fill white circle {radius},{radius} {radius},0",
            "(", "+clone", "-flip", ")", "-compose", "Multiply", "-composite",
            "(", "+clone", "-flop", ")", "-compose", "Multiply", "-composite", ")",
            "-alpha", "off", "-compose", "CopyOpacity", "-composite", tmp,
        )
        # Canvas: near-black with a mint and a sage glow, then caption, then the screenshot.
        run(
            "convert", "-size", f"{w}x{h}", "xc:#0A0A0A",
            "(", "-size", f"{w}x{h}", "radial-gradient:rgba(89,242,189,0.22)-rgba(10,10,10,0)", ")",
            "-gravity", "NorthEast", "-geometry", f"+{-w//4}+{-h//3}", "-compose", "Screen", "-composite",
            "-gravity", "North", "-font", BOLD, "-pointsize", str(cap_size), "-fill", "#F4F6F5",
            "-interline-spacing", "-6", "-annotate", f"+0+{cap_y}", title.replace("\\n", "\n"),
            "-font", MEDIUM, "-pointsize", str(sub_size), "-fill", "#95ABA7",
            "-annotate", f"+0+{cap_y + cap_size * 2 + 38}", sub,
            "(", tmp, "(", "+clone", "-background", "black", "-shadow", "55x28+0+18", ")", "+swap",
            "-background", "none", "-layers", "merge", "+repage", ")",
            "-gravity", "North", "-compose", "Over", "-geometry", f"+0+{shot_y}", "-composite",
            "-depth", "8", dst,
        )
        os.remove(tmp)
        print("wrote", dst)
