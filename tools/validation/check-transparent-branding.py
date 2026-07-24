#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# GenixBit OS branding transparent asset validator.

import os
import re
import sys
import base64
from io import BytesIO
from PIL import Image, ImageDraw

# Target directories to scan
TARGET_DIRS = [
    "packages/genixbit-os-theme/usr/share/genixbit/branding/",
    "packages/genixbit-os-theme/usr/share/pixmaps/",
    "packages/genixbit-os-theme/usr/share/icons/hicolor/",
    "packages/genixbit-os-installer-config/usr/share/genixbit-os-installer-config/branding/"
]

PREVIEWS_DIR = "packages/build-debs/previews"
os.makedirs(PREVIEWS_DIR, exist_ok=True)

def generate_checkerboard(width, height, color1, color2, square_size=16):
    bg = Image.new("RGBA", (width, height), color1)
    draw = ImageDraw.Draw(bg)
    for y in range(0, height, square_size):
        for x in range(0, width, square_size):
            if ((x // square_size) + (y // square_size)) % 2 == 1:
                draw.rectangle([x, y, x + square_size, y + square_size], fill=color2)
    return bg

def generate_previews(img, base_name):
    w, h = img.size
    # Dark background (Navy/Deep Blue)
    dark_cb = generate_checkerboard(w, h, (6, 19, 33, 255), (11, 30, 49, 255))
    dark_cb.alpha_composite(img)
    dark_cb.save(os.path.join(PREVIEWS_DIR, f"{base_name}_preview_dark.png"), "PNG")

    # Light background
    light_cb = generate_checkerboard(w, h, (221, 247, 252, 255), (255, 255, 255, 255))
    light_cb.alpha_composite(img)
    light_cb.save(os.path.join(PREVIEWS_DIR, f"{base_name}_preview_light.png"), "PNG")

    # Mid-grey background
    grey_cb = generate_checkerboard(w, h, (110, 110, 110, 255), (150, 150, 150, 255))
    grey_cb.alpha_composite(img)
    grey_cb.save(os.path.join(PREVIEWS_DIR, f"{base_name}_preview_grey.png"), "PNG")

def check_png_transparency(img, file_path, is_light=False):
    # Rule 1: PNG icons must use RGBA
    if img.mode != "RGBA":
        print(f"[FAIL] {file_path} is in mode {img.mode}, expected RGBA")
        return False

    w, h = img.size

    # Rule 2: Canvas corners must have alpha 0
    corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
    for x, y in corners:
        pixel = img.getpixel((x, y))
        if pixel[3] != 0:
            print(f"[FAIL] Corner ({x}, {y}) of {file_path} is opaque: {pixel}")
            return False

    # Rule 3, 4, 5: Check perimeter/borders for transparency to ensure no opaque rectangle
    # Check top/bottom rows
    for x in range(w):
        for y in [0, h - 1]:
            pixel = img.getpixel((x, y))
            if pixel[3] != 0:
                print(f"[FAIL] Border pixel ({x}, {y}) of {file_path} has alpha: {pixel[3]}")
                return False
    # Check left/right columns
    for y in range(h):
        for x in [0, w - 1]:
            pixel = img.getpixel((x, y))
            if pixel[3] != 0:
                print(f"[FAIL] Border pixel ({x}, {y}) of {file_path} has alpha: {pixel[3]}")
                return False

    # Rule 6: White logo variants mean white glyphs on transparent canvas
    if is_light:
        data = img.get_flattened_data() if hasattr(img, "get_flattened_data") else img.getdata()
        for i, pixel in enumerate(data):

            if pixel[3] > 0: # Non-transparent
                # Must be white or near white
                if pixel[0] < 235 or pixel[1] < 235 or pixel[2] < 235:
                    x = i % w
                    y = i // w
                    print(f"[FAIL] Light logo {file_path} has non-white pixel at ({x}, {y}): {pixel}")
                    return False

    return True

def extract_base64_png(svg_path):
    with open(svg_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Rule 7: SVG files must not contain an opaque full-canvas background rectangle
    # Check for `<rect` with solid color fill that is not none/transparent or fill-opacity="0"
    rect_matches = re.findall(r'<rect[^>]*>', content)
    for rect in rect_matches:
        if 'fill=' in rect:
            fill_val = re.search(r'fill="([^"]+)"', rect)
            if fill_val:
                val = fill_val.group(1)
                # If fill is not none/transparent and no fill-opacity=0 is defined
                if val not in ["none", "transparent"] and not ('fill-opacity="0"' in rect or 'opacity="0"' in rect):
                    print(f"[FAIL] SVG {svg_path} contains opaque background rectangle: {rect}")
                    return None

    # Rule 8: Embedded PNG data inside SVG files must itself have alpha transparency
    data_match = re.search(r'href="data:image/png;base64,([^"]+)"', content)
    if not data_match:
        # Check src= or xlink:href= just in case
        data_match = re.search(r'xlink:href="data:image/png;base64,([^"]+)"', content)
        
    if data_match:
        b64_data = data_match.group(1)
        try:
            img_data = base64.b64decode(b64_data)
            return Image.open(BytesIO(img_data))
        except Exception as e:
            print(f"[FAIL] Could not decode base64 PNG in SVG {svg_path}: {e}")
            return None
    else:
        print(f"[FAIL] SVG {svg_path} does not contain embedded base64 PNG image")
        return None

def main():
    print("Starting transparent branding assets validation...")
    failed = False
    checked_count = 0

    for d in TARGET_DIRS:
        if not os.path.exists(d):
            continue
        for root, _, files in os.walk(d):
            for file in files:
                file_path = os.path.join(root, file)
                
                # Rule 9, 10: Wallpapers and branding/source are exempt
                if "wallpapers" in file_path or "branding/source" in file_path:
                    continue
                
                is_light = "light" in file.lower()
                base_name = os.path.splitext(file)[0]
                
                if file.endswith(".png"):
                    checked_count += 1
                    try:
                        with Image.open(file_path) as img:
                            if not check_png_transparency(img, file_path, is_light):
                                failed = True
                            else:
                                generate_previews(img, f"{base_name}_png")
                    except Exception as e:
                        print(f"[FAIL] Error reading PNG {file_path}: {e}")
                        failed = True
                
                elif file.endswith(".svg"):
                    checked_count += 1
                    img = extract_base64_png(file_path)
                    if img is None:
                        failed = True
                    else:
                        if not check_png_transparency(img, file_path, is_light):
                            failed = True
                        else:
                            generate_previews(img, f"{base_name}_svg")
                            img.close()

    print(f"Validation completed. Checked {checked_count} branding files.")
    if failed:
        print("[STATUS] TRANSPARENT BRANDING VALIDATION: FAIL")
        sys.exit(1)
    else:
        print("[STATUS] TRANSPARENT BRANDING VALIDATION: PASS")
        sys.exit(0)

if __name__ == "__main__":
    main()
