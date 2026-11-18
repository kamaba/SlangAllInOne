"""Generate the MainMenu atlas: pre-rendered title + scene labels (no font runtime yet)."""
from PIL import Image, ImageDraw, ImageFont

W, H = 512, 256
img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

try:
    font_title = ImageFont.truetype("arialbd.ttf", 22)
    font_label = ImageFont.truetype("arial.ttf", 13)
except OSError:
    font_title = ImageFont.load_default()
    font_label = ImageFont.load_default()

# panel + button (same visual language as the Demo package)
d.rounded_rectangle((0, 0, 119, 79), radius=12, fill=(24, 38, 66, 255),
                    outline=(110, 170, 255, 255), width=3)
d.rectangle((8, 8, 111, 71), outline=(56, 92, 150, 255), width=1)
d.rounded_rectangle((128, 0, 207, 31), radius=8, fill=(46, 116, 190, 255),
                    outline=(150, 210, 255, 255), width=2)
d.rectangle((136, 5, 199, 9), fill=(120, 190, 255, 255))

d.text((6, 100), "SCENE SELECT", font=font_title, fill=(235, 245, 255, 255))

names = [
    "1   Material Ball",
    "2   Shape Gallery",
    "3   Pure Logic",
    "4   Material Gallery",
    "5   Rotate Test",
]
for i, text in enumerate(names):
    y = 160 + i * 18
    d.text((2, y), text, font=font_label, fill=(255, 245, 210, 255),
           stroke_width=1, stroke_fill=(10, 20, 40, 255))

d.rectangle((480, 240, 487, 247), fill=(255, 255, 255, 255))

img.save("atlas@menu.png")
print("atlas@menu.png written")
