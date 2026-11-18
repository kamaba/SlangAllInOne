"""Build the minimal .fui binary sample from the XML package (same UI data)."""
import struct
import xml.etree.ElementTree as ET

pkg = ET.parse("package.xml").getroot()
comp = ET.parse("DemoUI.xml").getroot()
dw = int(pkg.get("designWidth", "480"))
dh = int(pkg.get("designHeight", "480"))

atlas = pkg.find("atlas")
aw = int(atlas.get("width", "256"))
ah = int(atlas.get("height", "256"))
sprites = list(atlas.findall("sprite"))

# Parse component tree into the same flattened absolute quads the SL XML loader makes.
quads = []


def walk(node, ox, oy):
    for child in node:
        tag = child.tag
        if tag not in ("group", "image", "text"):
            continue
        x = ox + float(child.get("x", "0"))
        y = oy + float(child.get("y", "0"))
        if tag == "group":
            walk(child, x, y)
            continue
        src = child.get("src", "")
        if tag == "text" or not src:
            src = "white"
        si = next((i for i, s in enumerate(sprites) if s.get("name") == src), -1)
        quads.append((2 if tag == "text" else 0, x, y,
                      float(child.get("w", "0")), float(child.get("h", "0")),
                      si, 1 if child.get("scale9") == "1" else 0))


walk(comp, 0.0, 0.0)

out = bytearray()
out += b"FUI\x00"
out += struct.pack("<iiii", 1, dw, dh, aw)
out += struct.pack("<i", ah)
out += struct.pack("<i", len(sprites))
for s in sprites:
    b = [0, 0, 0, 0]
    if s.get("scale9"):
        b = [float(v) for v in s.get("scale9").split(",")]
        b += [0.0] * (4 - len(b))
    out += struct.pack("<8f", float(s.get("x", "0")), float(s.get("y", "0")),
                       float(s.get("w", "0")), float(s.get("h", "0")),
                       b[0], b[1], b[2], b[3])
    out += b"\x00" * 4
out += struct.pack("<i", len(quads))
for q in quads:
    out += struct.pack("<iffffii", *q)

with open("Demo.fui", "wb") as f:
    f.write(out)
print(f"Demo.fui written: {len(sprites)} sprites, {len(quads)} quads, {len(out)} bytes")
