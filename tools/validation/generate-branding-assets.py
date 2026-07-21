#!/usr/bin/env python3
import os
import base64
from io import BytesIO
from PIL import Image, ImageOps

def create_dirs():
    dirs = [
        "packages/genixbit-os-theme/usr/share/genixbit/branding",
        "packages/genixbit-os-theme/usr/share/pixmaps",
        "packages/genixbit-os-wallpapers/usr/share/backgrounds/genixbit",
        "packages/genixbit-os-installer-config/usr/share/genixbit-os-installer-config/branding"
    ]
    # App icon dirs
    sizes = [16, 32, 48, 64, 128, 256, 512]
    for s in sizes:
        dirs.append(f"packages/genixbit-os-theme/usr/share/icons/hicolor/{s}x{s}/apps")
    
    for d in dirs:
        os.makedirs(d, exist_ok=True)

def remove_background(img, threshold=240):
    # Convert image to RGBA
    rgba = img.convert("RGBA")
    data = rgba.getdata()
    
    new_data = []
    for item in data:
        # Detect light background pixels (close to #E6F7FF or pure white)
        # Red > threshold, Green > threshold-10, Blue > threshold
        if item[0] > 210 and item[1] > 230 and item[2] > 240:
            new_data.append((255, 255, 255, 0))
        elif item[0] > 245 and item[1] > 245 and item[2] > 245:
            new_data.append((255, 255, 255, 0))
        else:
            new_data.append(item)
            
    rgba.putdata(new_data)
    return rgba

def make_monochrome(img, color=(255, 255, 255)):
    # Converts all non-transparent pixels to a single solid color
    rgba = img.convert("RGBA")
    data = rgba.getdata()
    
    new_data = []
    for item in data:
        if item[3] > 0: # non-transparent
            new_data.append((color[0], color[1], color[2], item[3]))
        else:
            new_data.append(item)
    rgba.putdata(new_data)
    return rgba

def get_bbox_crop(img, area_y_start=0.0, area_y_end=1.0):
    # Find bounding box of non-transparent pixels in the given Y-ratio range
    width, height = img.size
    rgba = img.convert("RGBA")
    
    # We restrict search to specific Y coordinates to isolate monogram/wordmark
    y_start = int(height * area_y_start)
    y_end = int(height * area_y_end)
    
    min_x, min_y = width, height
    max_x, max_y = 0, 0
    
    for y in range(y_start, y_end):
        for x in range(width):
            pixel = rgba.getpixel((x, y))
            if pixel[3] > 10: # alpha threshold
                if x < min_x: min_x = x
                if y < min_y: min_y = y
                if x > max_x: max_x = x
                if y > max_y: max_y = y
                
    if max_x >= min_x and max_y >= min_y:
        return img.crop((min_x, min_y, max_x + 1, max_y + 1))
    return img

def make_square(img, pad_color=(0, 0, 0, 0)):
    # Pads a rectangular image to a perfect square without stretching
    width, height = img.size
    if width == height:
        return img
    elif width > height:
        result = Image.new("RGBA", (width, width), pad_color)
        result.paste(img, (0, (width - height) // 2))
        return result
    else:
        result = Image.new("RGBA", (height, height), pad_color)
        result.paste(img, (((height - width) // 2), 0))
        return result

def add_transparent_padding(img, padding_ratio=0.05):
    # Adds a percentage of transparent padding to all four sides of the image
    width, height = img.size
    pad_w = int(width * padding_ratio)
    pad_h = int(height * padding_ratio)
    if pad_w == 0: pad_w = 1
    if pad_h == 0: pad_h = 1
    
    new_w = width + 2 * pad_w
    new_h = height + 2 * pad_h
    
    padded_img = Image.new("RGBA", (new_w, new_h), (0, 0, 0, 0))
    padded_img.paste(img, (pad_w, pad_h))
    return padded_img

def zero_borders(img):
    # Forces all border pixels of an image to be completely transparent
    w, h = img.size
    rgba = img.convert("RGBA")
    pixels = list(rgba.getdata())
    for y in range(h):
        for x in range(w):
            if x == 0 or x == w - 1 or y == 0 or y == h - 1:
                idx = y * w + x
                pixels[idx] = (pixels[idx][0], pixels[idx][1], pixels[idx][2], 0)
    rgba.putdata(pixels)
    return rgba

def image_to_base64_png(img):
    buffered = BytesIO()
    img.save(buffered, format="PNG")
    return base64.b64encode(buffered.getvalue()).decode('utf-8')

def save_svg_embedded(img, filename, view_width=512, view_height=512):
    b64_str = image_to_base64_png(img)
    svg_content = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {view_width} {view_height}" width="100%" height="100%">
  <image href="data:image/png;base64,{b64_str}" width="{view_width}" height="{view_height}"/>
</svg>
'''
    with open(filename, 'w') as f:
        f.write(svg_content)

def main():
    print("Initializing branding asset generation...")
    create_dirs()
    
    # Load source files
    square_src_path = "branding/source/genixbit-approved-square.jpg"
    horiz_src_path = "branding/source/genixbit-approved-horizontal.png"
    ref3d_src_path = "branding/source/genixbit-3d-reference.png"
    
    if not (os.path.exists(square_src_path) and os.path.exists(horiz_src_path) and os.path.exists(ref3d_src_path)):
        print("BLOCKED_APPROVED_LOGO_ASSETS_MISSING")
        return
        
    img_square = Image.open(square_src_path)
    img_horiz = Image.open(horiz_src_path)
    img_ref3d = Image.open(ref3d_src_path)
    
    # Process Monogram (Mark)
    # Background transparent
    square_trans = remove_background(img_square)
    monogram = get_bbox_crop(square_trans, 0.0, 0.7)
    monogram = add_transparent_padding(monogram, 0.05)
    # Pad to square
    monogram_square = make_square(monogram)
    monogram_square = zero_borders(monogram_square)
    
    # Generate PNG icon sizes
    sizes = [16, 32, 48, 64, 128, 256, 512]
    for s in sizes:
        icon_resized = monogram_square.resize((s, s), Image.Resampling.LANCZOS)
        icon_resized = zero_borders(icon_resized)
        icon_resized.save(f"packages/genixbit-os-theme/usr/share/icons/hicolor/{s}x{s}/apps/genixbit-mark.png", "PNG")
        
    # Also save a standard pixmaps size
    pixmap_resized = monogram_square.resize((256, 256), Image.Resampling.LANCZOS)
    pixmap_resized = zero_borders(pixmap_resized)
    pixmap_resized.save("packages/genixbit-os-theme/usr/share/pixmaps/genixbit-mark.png", "PNG")
    
    # Create dark-themed and light-themed monogram variants
    monogram_dark = monogram_square # default `#0083A8` is dark
    monogram_light = make_monochrome(monogram_square, (255, 255, 255)) # white
    
    # Save SVG marks
    save_svg_embedded(monogram_square, "packages/genixbit-os-theme/usr/share/genixbit/branding/genixbit-mark.svg")
    save_svg_embedded(monogram_dark, "packages/genixbit-os-theme/usr/share/genixbit/branding/genixbit-mark-dark.svg")
    save_svg_embedded(monogram_light, "packages/genixbit-os-theme/usr/share/genixbit/branding/genixbit-mark-light.svg")
    save_svg_embedded(monogram_square, "packages/genixbit-os-theme/usr/share/pixmaps/genixbit-mark.svg")
    
    # Also copy logo to installer config branding
    save_svg_embedded(monogram_square, "packages/genixbit-os-installer-config/usr/share/genixbit-os-installer-config/branding/genixbit-logo.svg")
    
    wordmark = get_bbox_crop(square_trans, 0.7, 1.0)
    wordmark = add_transparent_padding(wordmark, 0.05)
    wordmark = zero_borders(wordmark)
    # Save wordmark SVG
    w_width, w_height = wordmark.size
    save_svg_embedded(wordmark, "packages/genixbit-os-theme/usr/share/genixbit/branding/genixbit-wordmark.svg", w_width, w_height)
    # Also copy to installer config
    save_svg_embedded(wordmark, "packages/genixbit-os-installer-config/usr/share/genixbit-os-installer-config/branding/genixbit-wordmark.svg", w_width, w_height)
    
    horiz_trans = remove_background(img_horiz)
    lockup = get_bbox_crop(horiz_trans)
    lockup = add_transparent_padding(lockup, 0.05)
    lockup = zero_borders(lockup)
    l_width, l_height = lockup.size
    
    # Create variants of lockup (standard, light, dark)
    # For standard and dark, keep original
    lockup_dark = lockup
    # For light (on dark background), make the whole lockup white
    lockup_light = make_monochrome(lockup, (255, 255, 255))
    
    save_svg_embedded(lockup, "packages/genixbit-os-theme/usr/share/genixbit/branding/genixbit-lockup.svg", l_width, l_height)
    save_svg_embedded(lockup_dark, "packages/genixbit-os-theme/usr/share/genixbit/branding/genixbit-lockup-dark.svg", l_width, l_height)
    save_svg_embedded(lockup_light, "packages/genixbit-os-theme/usr/share/genixbit/branding/genixbit-lockup-light.svg", l_width, l_height)
    
    # Process Wallpapers (3D Reference)
    # Wallpaper sizes: 1920x1080, 2560x1440, 3840x2160
    wallpapers_info = [
        (1920, 1080),
        (2560, 1440),
        (3840, 2160)
    ]
    for w, h in wallpapers_info:
        # Scale & Crop to fit exact aspect ratio
        wp_resized = ImageOps.fit(img_ref3d, (w, h), Image.Resampling.LANCZOS)
        wp_resized.save(f"packages/genixbit-os-wallpapers/usr/share/backgrounds/genixbit/genixbit-wallpaper-{w}x{h}.png", "PNG")
        # Save SVG variant as well
        save_svg_embedded(wp_resized, f"packages/genixbit-os-wallpapers/usr/share/backgrounds/genixbit/genixbit-wallpaper-{w}x{h}.svg", w, h)
        
    # Create default light and dark links/copies
    wp_dark = ImageOps.fit(img_ref3d, (1920, 1080), Image.Resampling.LANCZOS)
    wp_dark.save("packages/genixbit-os-wallpapers/usr/share/backgrounds/genixbit/genixbit-wallpaper-dark.png", "PNG")
    save_svg_embedded(wp_dark, "packages/genixbit-os-wallpapers/usr/share/backgrounds/genixbit/genixbit-wallpaper-dark.svg", 1920, 1080)
    
    # Create a light wallpaper by adjusting brightness/contrast of the 3D reference or blending with light background
    # Let's blend it or create a clean light version using the light background `#DDF7FC`
    wp_light = Image.new("RGBA", (1920, 1080), (221, 247, 252, 255)) # #DDF7FC
    # Overlay the lockup or a scaled version of the monogram in the center
    mono_for_wp = monogram_square.resize((350, 350), Image.Resampling.LANCZOS)
    wp_light.paste(mono_for_wp, ((1920 - 350) // 2, (1080 - 350) // 2), mono_for_wp)
    wp_light.save("packages/genixbit-os-wallpapers/usr/share/backgrounds/genixbit/genixbit-wallpaper-light.png", "PNG")
    save_svg_embedded(wp_light, "packages/genixbit-os-wallpapers/usr/share/backgrounds/genixbit/genixbit-wallpaper-light.svg", 1920, 1080)
    
    print("Branding assets generated successfully.")
    print("VECTOR_MASTER_REQUIRES_MANUAL_APPROVAL")

if __name__ == "__main__":
    main()
