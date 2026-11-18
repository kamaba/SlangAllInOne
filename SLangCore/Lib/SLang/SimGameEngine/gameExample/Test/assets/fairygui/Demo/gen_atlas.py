"""Generate the minimal FairyGUI-style atlas PNG used by SceneDemo's UI smoke test."""
from PIL import Image, ImageDraw

W = H = 256
img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# panel: (0,0,120,80) - dark blue rounded panel with a lighter border
d.rounded_rectangle((0, 0, 119, 79), radius=12, fill=(38, 62, 104, 255), outline=(120, 180, 255, 255), width=3)
d.rectangle((8, 8, 111, 71), outline=(70, 110, 175, 255), width=1)

# btn: (128,0,80,32) - green button with a highlight strip
d.rounded_rectangle((128, 0, 207, 31), radius=8, fill=(46, 150, 90, 255), outline=(150, 240, 180, 255), width=2)
d.rectangle((136, 5, 199, 9), fill=(110, 220, 150, 255))

# icon: (0,96,48,48) - amber tile with an inset diamond
d.rectangle((0, 96, 47, 143), fill=(240, 176, 48, 255), outline=(255, 230, 150, 255), width=2)
d.polygon([(24, 102), (42, 120), (24, 138), (6, 120)], fill=(255, 220, 130, 255))

# white: (200,200,8,8) - solid white pixel block (text placeholder tint source)
d.rectangle((200, 200, 207, 207), fill=(255, 255, 255, 255))

img.save("atlas@ui.png")
print("atlas@ui.png written")
