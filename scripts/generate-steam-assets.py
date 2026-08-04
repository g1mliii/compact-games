from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


SPECS = {
    "header_capsule.jpg": (920, 430, True),
    "small_capsule.jpg": (462, 174, True),
    "main_capsule.jpg": (1232, 706, True),
    "vertical_capsule.jpg": (748, 896, True),
    "library_capsule.jpg": (600, 900, True),
    "library_hero.png": (3840, 1240, False),
    "library_header_capsule.jpg": (920, 430, True),
    "page_background.jpg": (1438, 810, False),
}


def cover_crop(image: Image.Image, size: tuple[int, int], anchor_x: float) -> Image.Image:
    width, height = size
    scale = max(width / image.width, height / image.height)
    resized = image.resize(
        (round(image.width * scale), round(image.height * scale)),
        Image.Resampling.LANCZOS,
    )
    left = round(anchor_x * resized.width - anchor_x * width)
    top = round((resized.height - height) / 2)
    left = max(0, min(left, resized.width - width))
    top = max(0, min(top, resized.height - height))
    return resized.crop((left, top, left + width, top + height))


def font_for(size: int) -> ImageFont.FreeTypeFont:
    candidates = (
        Path(r"C:\Windows\Fonts\seguisb.ttf"),
        Path(r"C:\Windows\Fonts\segoeuib.ttf"),
        Path(r"C:\Windows\Fonts\arialbd.ttf"),
    )
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size=size)
    raise FileNotFoundError("No supported bold Windows font was found.")


def add_wordmark(image: Image.Image, icon: Image.Image, portrait: bool) -> None:
    draw = ImageDraw.Draw(image, "RGBA")
    width, height = image.size

    if portrait:
        gradient_height = round(height * 0.37)
        for y in range(gradient_height):
            alpha = round(225 * (1 - y / gradient_height))
            draw.rectangle((0, y, width, y + 1), fill=(6, 16, 29, alpha))
        font_size = max(34, round(width * 0.105))
        font = font_for(font_size)
        text = "Compact Games"
        box = draw.textbbox((0, 0), text, font=font)
        text_width = box[2] - box[0]
        while text_width > width * 0.86 and font_size > 24:
            font_size -= 2
            font = font_for(font_size)
            box = draw.textbbox((0, 0), text, font=font)
            text_width = box[2] - box[0]
        x = round((width - text_width) / 2)
        y = round(height * 0.075)
        icon_size = round(font_size * 1.15)
        icon_copy = icon.resize((icon_size, icon_size), Image.Resampling.LANCZOS)
        total_width = icon_size + round(font_size * 0.24) + text_width
        icon_x = max(round(width * 0.06), round((width - total_width) / 2))
        image.alpha_composite(icon_copy, (icon_x, y - round(font_size * 0.12)))
        x = icon_x + icon_size + round(font_size * 0.24)
    else:
        gradient_width = round(width * 0.6)
        for x_value in range(gradient_width):
            alpha = round(232 * (1 - x_value / gradient_width))
            draw.rectangle((x_value, 0, x_value + 1, height), fill=(6, 16, 29, alpha))
        font_size = max(24, round(height * 0.17))
        font = font_for(font_size)
        text = "Compact Games"
        box = draw.textbbox((0, 0), text, font=font)
        text_width = box[2] - box[0]
        while text_width > width * 0.51 and font_size > 18:
            font_size -= 2
            font = font_for(font_size)
            box = draw.textbbox((0, 0), text, font=font)
            text_width = box[2] - box[0]
        icon_size = round(font_size * 1.25)
        icon_copy = icon.resize((icon_size, icon_size), Image.Resampling.LANCZOS)
        x = round(width * 0.055)
        y = round((height - font_size) / 2 - font_size * 0.12)
        image.alpha_composite(icon_copy, (x, y - round(font_size * 0.18)))
        x += icon_size + round(font_size * 0.25)

    draw.text(
        (x, y),
        text,
        font=font,
        fill=(245, 248, 252, 255),
        stroke_width=max(1, round(font_size * 0.025)),
        stroke_fill=(3, 11, 20, 210),
    )


def save_rgb(image: Image.Image, destination: Path) -> None:
    if destination.suffix.lower() == ".jpg":
        image.convert("RGB").save(destination, quality=94, optimize=True, progressive=True)
    else:
        image.save(destination, optimize=True)


def generate(master_path: Path, icon_path: Path, output_dir: Path) -> None:
    master = Image.open(master_path).convert("RGBA")
    icon = Image.open(icon_path).convert("RGBA")
    output_dir.mkdir(parents=True, exist_ok=True)

    for filename, (width, height, wordmark) in SPECS.items():
        portrait = height > width
        anchor_x = 0.66 if portrait else 0.57
        asset = cover_crop(master, (width, height), anchor_x).convert("RGBA")
        if wordmark:
            add_wordmark(asset, icon, portrait)
        save_rgb(asset, output_dir / filename)

    shortcut = icon.resize((256, 256), Image.Resampling.LANCZOS)
    shortcut.save(output_dir / "shortcut_icon.png", optimize=True)

    app_icon = Image.new("RGB", (184, 184), (9, 20, 34))
    app_icon.paste(icon.resize((168, 168), Image.Resampling.LANCZOS), (8, 8), icon.resize((168, 168), Image.Resampling.LANCZOS))
    app_icon.save(output_dir / "app_icon.jpg", quality=95, optimize=True)

    logo = Image.new("RGBA", (1280, 360), (0, 0, 0, 0))
    draw = ImageDraw.Draw(logo)
    logo_icon = icon.resize((300, 300), Image.Resampling.LANCZOS)
    logo.alpha_composite(logo_icon, (20, 30))
    font_size = 142
    font = font_for(font_size)
    text = "Compact Games"
    text_box = draw.textbbox((0, 0), text, font=font, stroke_width=3)
    while text_box[2] - text_box[0] > 890 and font_size > 72:
        font_size -= 2
        font = font_for(font_size)
        text_box = draw.textbbox((0, 0), text, font=font, stroke_width=3)
    draw.text(
        (350, round((360 - font_size) / 2 - font_size * 0.1)),
        text,
        font=font,
        fill=(245, 248, 252, 255),
        stroke_width=3,
        stroke_fill=(3, 11, 20, 230),
    )
    logo.save(output_dir / "library_logo.png", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Steam capsules from Compact Games key art.")
    parser.add_argument("--master", type=Path, required=True)
    parser.add_argument("--icon", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    generate(args.master.resolve(), args.icon.resolve(), args.out.resolve())


if __name__ == "__main__":
    main()
