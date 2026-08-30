#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Validate GenixBit OS branding assets for real transparent rendering."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw

TARGET_DIRS = [
    "packages/genixbit-os-theme/usr/share/genixbit/branding/",
    "packages/genixbit-os-theme/usr/share/pixmaps/",
    "packages/genixbit-os-theme/usr/share/icons/hicolor/",
    "packages/genixbit-os-installer-config/usr/share/genixbit-os-installer-config/branding/",
]

PREVIEWS_DIR = "packages/build-debs/previews"
os.makedirs(PREVIEWS_DIR, exist_ok=True)


def generate_checkerboard(width, height, color1, color2, square_size=16):
    bg = Image.new("RGBA", (width, height), color1)
    draw = ImageDraw.Draw(bg)
    for y in range(0, height, square_size):
        for x in range(0, width, square_size):
            if ((x // square_size) + (y // square_size)) % 2 == 1:
                draw.rectangle(
                    [x, y, min(x + square_size, width - 1), min(y + square_size, height - 1)],
                    fill=color2,
                )
    return bg


def generate_previews(img, base_name):
    rgba = img.convert("RGBA")
    w, h = rgba.size
    backgrounds = {
        "dark": ((6, 19, 33, 255), (11, 30, 49, 255)),
        "light": ((221, 247, 252, 255), (255, 255, 255, 255)),
        "grey": ((110, 110, 110, 255), (150, 150, 150, 255)),
    }
    for suffix, (first, second) in backgrounds.items():
        preview = generate_checkerboard(w, h, first, second)
        preview.alpha_composite(rgba)
        preview.save(os.path.join(PREVIEWS_DIR, f"{base_name}_preview_{suffix}.png"), "PNG")


def check_png_transparency(img, file_path, is_light=False):
    rgba = img.convert("RGBA") if img.mode != "RGBA" else img
    if img.mode != "RGBA" and file_path.lower().endswith(".png"):
        print(f"[FAIL] {file_path} is in mode {img.mode}, expected RGBA")
        return False

    w, h = rgba.size
    if w < 2 or h < 2:
        print(f"[FAIL] {file_path} has invalid dimensions: {w}x{h}")
        return False

    corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
    for x, y in corners:
        pixel = rgba.getpixel((x, y))
        if pixel[3] != 0:
            print(f"[FAIL] Corner ({x}, {y}) of {file_path} is opaque: {pixel}")
            return False

    for x in range(w):
        for y in (0, h - 1):
            alpha = rgba.getpixel((x, y))[3]
            if alpha != 0:
                print(f"[FAIL] Border pixel ({x}, {y}) of {file_path} has alpha: {alpha}")
                return False
    for y in range(h):
        for x in (0, w - 1):
            alpha = rgba.getpixel((x, y))[3]
            if alpha != 0:
                print(f"[FAIL] Border pixel ({x}, {y}) of {file_path} has alpha: {alpha}")
                return False

    if is_light:
        for i, pixel in enumerate(rgba.getdata()):
            if pixel[3] > 0 and (pixel[0] < 235 or pixel[1] < 235 or pixel[2] < 235):
                x = i % w
                y = i // w
                print(f"[FAIL] Light logo {file_path} has non-white pixel at ({x}, {y}): {pixel}")
                return False

    return True


def _numeric(value):
    if value is None:
        return None
    match = re.fullmatch(r"\s*(-?(?:\d+(?:\.\d*)?|\.\d+))(?:px)?\s*", value)
    return float(match.group(1)) if match else None


def _is_opaque_fill(rect):
    fill = rect.attrib.get("fill", "")
    style = rect.attrib.get("style", "")
    if not fill and style:
        match = re.search(r"(?:^|;)\s*fill\s*:\s*([^;]+)", style)
        fill = match.group(1).strip() if match else ""

    if not fill or fill in {"none", "transparent"}:
        return False

    for value in (rect.attrib.get("opacity"), rect.attrib.get("fill-opacity")):
        if value is not None:
            numeric = _numeric(value)
            if numeric is not None and numeric <= 0:
                return False
    return True


def svg_has_opaque_full_canvas_rect(svg_path):
    """Return True only for a rectangle that actually covers the whole SVG canvas."""
    try:
        root = ET.parse(svg_path).getroot()
    except (ET.ParseError, OSError) as exc:
        print(f"[FAIL] Could not parse SVG {svg_path}: {exc}")
        return True

    view_box = root.attrib.get("viewBox", "").replace(",", " ").split()
    canvas = None
    if len(view_box) == 4:
        try:
            min_x, min_y, width, height = map(float, view_box)
            canvas = (min_x, min_y, width, height)
        except ValueError:
            pass

    if canvas is None:
        width = _numeric(root.attrib.get("width"))
        height = _numeric(root.attrib.get("height"))
        if width is not None and height is not None:
            canvas = (0.0, 0.0, width, height)

    if canvas is None:
        return False

    min_x, min_y, width, height = canvas
    for rect in root.iter():
        if not rect.tag.endswith("rect") or not _is_opaque_fill(rect):
            continue

        x = _numeric(rect.attrib.get("x", "0"))
        y = _numeric(rect.attrib.get("y", "0"))
        rect_width = rect.attrib.get("width")
        rect_height = rect.attrib.get("height")
        covers_width = rect_width == "100%" or _numeric(rect_width) == width
        covers_height = rect_height == "100%" or _numeric(rect_height) == height
        if x == min_x and y == min_y and covers_width and covers_height:
            print(f"[FAIL] SVG {svg_path} contains an opaque full-canvas background rectangle")
            return True

    return False


def render_svg(svg_path):
    renderer = shutil.which("rsvg-convert")
    if not renderer:
        print("[FAIL] rsvg-convert is required to validate SVG rendering")
        return None

    temp_path = None
    try:
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as handle:
            temp_path = handle.name
        subprocess.run(
            [renderer, svg_path, "-o", temp_path],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        with Image.open(temp_path) as rendered:
            return rendered.convert("RGBA").copy()
    except (OSError, subprocess.CalledProcessError) as exc:
        detail = exc.stderr.strip() if isinstance(exc, subprocess.CalledProcessError) and exc.stderr else str(exc)
        print(f"[FAIL] Could not render SVG {svg_path}: {detail}")
        return None
    finally:
        if temp_path:
            try:
                os.unlink(temp_path)
            except FileNotFoundError:
                pass


def validate_svg(file_path, is_light):
    if svg_has_opaque_full_canvas_rect(file_path):
        return False

    rendered = render_svg(file_path)
    if rendered is None:
        return False

    try:
        if not check_png_transparency(rendered, file_path, is_light):
            return False
        generate_previews(rendered, f"{os.path.splitext(os.path.basename(file_path))[0]}_svg")
        return True
    finally:
        rendered.close()


def main():
    print("Starting transparent branding assets validation...")
    failed = False
    checked_count = 0

    for directory in TARGET_DIRS:
        if not os.path.exists(directory):
            continue
        for root, _, files in os.walk(directory):
            for filename in files:
                file_path = os.path.join(root, filename)

                if "wallpapers" in file_path or "branding/source" in file_path:
                    continue

                lower = filename.lower()
                if not lower.endswith((".png", ".svg")):
                    continue

                checked_count += 1
                is_light = "light" in lower
                base_name = os.path.splitext(filename)[0]

                if lower.endswith(".png"):
                    try:
                        with Image.open(file_path) as img:
                            if not check_png_transparency(img, file_path, is_light):
                                failed = True
                            else:
                                generate_previews(img, f"{base_name}_png")
                    except Exception as exc:
                        print(f"[FAIL] Error reading PNG {file_path}: {exc}")
                        failed = True
                elif not validate_svg(file_path, is_light):
                    failed = True

    print(f"Validation completed. Checked {checked_count} branding files.")
    if failed:
        print("[STATUS] TRANSPARENT BRANDING VALIDATION: FAIL")
        return 1

    print("[STATUS] TRANSPARENT BRANDING VALIDATION: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
