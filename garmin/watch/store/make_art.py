"""Generate Connect IQ Store artwork for Strive.

Cover 500x500 and hero 1440x720, matching the app's dark/blue identity.
Text is rendered with a system font; no external assets required.
"""

from PIL import Image, ImageDraw, ImageFont
import os

OUT = os.path.dirname(os.path.abspath(__file__))
BG = (5, 5, 5)
BLUE = (59, 130, 246)
PURPLE = (139, 92, 246)
GREY = (148, 163, 184)

FONT_BOLD = r"C:\Windows\Fonts\segoeuib.ttf"
FONT_REG = r"C:\Windows\Fonts\segoeui.ttf"


def font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


def gradient(size, top, bottom):
    w, h = size
    img = Image.new("RGB", size, top)
    draw = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        colour = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        draw.line([(0, y), (w, y)], fill=colour)
    return img


def centre_text(draw, box, text, fnt, fill):
    left, top, right, bottom = draw.textbbox((0, 0), text, font=fnt)
    w, h = right - left, bottom - top
    x = (box[0] + box[2]) / 2 - w / 2 - left
    y = (box[1] + box[3]) / 2 - h / 2 - top
    draw.text((x, y), text, font=fnt, fill=fill)


def bar(draw, cx, cy, width, height, colour):
    draw.rounded_rectangle(
        [cx - width / 2, cy - height / 2, cx + width / 2, cy + height / 2],
        radius=height / 2, fill=colour,
    )
    plate_w = width * 0.08
    for side in (-1, 1):
        x = cx + side * (width / 2 - plate_w * 0.9)
        draw.rounded_rectangle(
            [x - plate_w / 2, cy - height * 1.5, x + plate_w / 2, cy + height * 1.5],
            radius=plate_w / 3, fill=colour,
        )


# --- cover 500x500 -----------------------------------------------------------
cover = gradient((500, 500), (14, 22, 48), BG)
d = ImageDraw.Draw(cover)
bar(d, 250, 150, 190, 16, BLUE)
centre_text(d, (0, 210, 500, 300), "STRIVE", font(FONT_BOLD, 84), (255, 255, 255))
centre_text(d, (0, 300, 500, 350), "GYM LOG", font(FONT_REG, 26), GREY)
d.rounded_rectangle([70, 380, 430, 382], radius=1, fill=PURPLE)
centre_text(d, (0, 395, 500, 440), "tells you what to lift next", font(FONT_REG, 22), GREY)
cover.save(os.path.join(OUT, "store_cover_500.png"))

# --- hero 1440x720 -----------------------------------------------------------
hero = gradient((1440, 720), (14, 22, 48), BG)
d = ImageDraw.Draw(hero)
bar(d, 300, 250, 260, 20, BLUE)
centre_text(d, (120, 300, 480, 400), "STRIVE", font(FONT_BOLD, 110), (255, 255, 255))
centre_text(d, (120, 400, 480, 450), "GYM LOG", font(FONT_REG, 30), GREY)

# fake "watch screen" card on the right
card = [760, 150, 1160, 570]
d.rounded_rectangle(card, radius=48, fill=(18, 18, 22), outline=(60, 60, 70), width=3)
centre_text(d, (760, 210, 1160, 270), "Bench Press", font(FONT_REG, 30), GREY)
centre_text(d, (760, 300, 1160, 400), "82.5", font(FONT_BOLD, 96), BLUE)
centre_text(d, (760, 400, 1160, 440), "kg", font(FONT_REG, 26), GREY)
centre_text(d, (760, 470, 1160, 510), "8 reps   sets 1", font(FONT_REG, 24), GREY)

centre_text(d, (760, 610, 1160, 660), "recommended load, on your wrist", font(FONT_REG, 22), GREY)
hero.save(os.path.join(OUT, "store_hero_1440x720.png"))

for name in ("store_cover_500.png", "store_hero_1440x720.png"):
    p = os.path.join(OUT, name)
    print(f"{name}: {os.path.getsize(p) // 1024} KB")
