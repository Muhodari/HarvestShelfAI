"""Draws the HarvestShelf logo from plain geometry (no external artwork).

    python scripts/make_logo.py

Writes app/assets/brand/:
  icon.png             1024 px app icon (rounded square)
  icon_foreground.png  1024 px Android adaptive-icon foreground (transparent)
  mark.png             1024 px mark only, transparent, for in-app use
  logo_preview.png     icon at several sizes, for review

The mark: a tomato and a hand of green cooking bananas on a market shelf,
framed by camera-scan corners - "scan what is on the shelf".
"""

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "app" / "assets" / "brand"
SS = 4  # supersampling factor for smooth edges
N = 1024

GREEN_TOP = (42, 122, 76)
GREEN_BOTTOM = (20, 70, 43)
CREAM = (247, 245, 238)
TOMATO = (232, 85, 61)
TOMATO_LIGHT = (246, 140, 112)
BANANA = (156, 196, 64)       # green cooking banana (matooke)
BANANA_BACK = (110, 158, 52)
BANANA_LIGHT = (196, 224, 112)
CROWN = (86, 108, 44)
LEAF = (123, 198, 126)


def s(v):
    return int(round(v * SS))


def box(cx, cy, rx, ry):
    return [s(cx - rx), s(cy - ry), s(cx + rx), s(cy + ry)]


def mask(draw_fn):
    m = Image.new("L", (N * SS, N * SS), 0)
    draw_fn(ImageDraw.Draw(m))
    return m


def paint(base, m, color):
    base.paste(Image.new("RGBA", base.size, color + (255,)), (0, 0), m)


def draw_mark(img, scale=1.0, offset=(0, 0)):
    """Draws the mark onto an RGBA canvas. Geometry is in 1024 units."""
    ox, oy = offset

    def T(x, y):
        return (ox + (x - 512) * scale + 512, oy + (y - 512) * scale + 512)

    def R(v):
        return v * scale

    d = ImageDraw.Draw(img)

    # Scan corners
    w = R(46)
    a, b, L = 196, 828, 150
    for (x, y, dx, dy) in [(a, a, 1, 1), (b, a, -1, 1), (a, b, 1, -1), (b, b, -1, -1)]:
        p0 = T(x, y + dy * L)
        p1 = T(x, y)
        p2 = T(x + dx * L, y)
        d.line([tuple(map(s, p0)), tuple(map(s, p1)), tuple(map(s, p2))],
               fill=CREAM + (255,), width=s(w), joint="curve")
        for p in (p0, p2):
            d.ellipse(box(p[0], p[1], w / 2, w / 2), fill=CREAM + (255,))
        d.ellipse(box(p1[0], p1[1], w / 2, w / 2), fill=CREAM + (255,))

    # Shelf
    x0, y0 = T(262, 662)
    x1, y1 = T(762, 700)
    d.rounded_rectangle([s(x0), s(y0), s(x1), s(y1)], radius=s(R(19)), fill=CREAM + (255,))

    # Banana hand (matooke): two curved fingers joined at a crown on the right.
    # Each finger is ellipse A minus ellipse B (a crescent, tips up).
    def finger(cx, cy, thick):
        ax, ay = T(cx, cy)
        bx, by = T(cx + 26, cy - thick)
        return ImageChops.subtract(
            mask(lambda m: m.ellipse(box(ax, ay, R(158), R(104)), fill=255)),
            mask(lambda m: m.ellipse(box(bx, by, R(168), R(104)), fill=255)),
        )

    back = finger(620, 512, 60)
    front = finger(636, 558, 62)
    paint(img, back, BANANA_BACK)
    paint(img, front, BANANA)
    stripe = ImageChops.multiply(finger(636, 548, 50), front)
    paint(img, stripe.point(lambda v: int(v * 0.6)), BANANA_LIGHT)

    # Crown: where the fingers meet on the right, found from the masks.
    def right_tip(m):
        bbox = m.getbbox()
        x = bbox[2] - 1
        col = [y for y in range(bbox[1], bbox[3]) if m.getpixel((x - s(6), y)) > 0]
        return x / SS, (sum(col) / len(col)) / SS

    (fx, fy), (bx2, by2) = right_tip(front), right_tip(back)
    cx_, cy_ = (fx + bx2) / 2 - R(8), (fy + by2) / 2
    d.rounded_rectangle([s(cx_ - R(10)), s(cy_ - R(30)), s(cx_ + R(34)), s(cy_ + R(22))],
                        radius=s(R(16)), fill=CROWN + (255,))
    d.rounded_rectangle([s(cx_ + R(22)), s(cy_ - R(16)), s(cx_ + R(54)), s(cy_ + R(6))],
                        radius=s(R(10)), fill=CROWN + (255,))

    # Tomato: sits on the shelf in front of the banana
    cx, cy = T(418, 548)
    r = R(118)
    d.ellipse(box(cx, cy, r * 1.06, r), fill=TOMATO + (255,))
    # highlight
    hx, hy = T(372, 506)
    hl = mask(lambda m: m.ellipse(box(hx, hy, R(34), R(22)), fill=255)).filter(ImageFilter.GaussianBlur(s(6)))
    paint(img, hl, TOMATO_LIGHT)
    # calyx: five small leaves
    import math
    kx, ky = T(418, 436)
    for i in range(5):
        ang = -math.pi / 2 + i * 2 * math.pi / 5
        ex, ey = kx + math.cos(ang) * R(30), ky + math.sin(ang) * R(18)
        leaf = mask(lambda m, ex=ex, ey=ey: m.ellipse(box((kx + ex) / 2, (ky + ey) / 2, R(22), R(11)), fill=255))
        leaf = leaf.rotate(-math.degrees(ang), center=(s((kx + ex) / 2), s((ky + ey) / 2)))
        paint(img, leaf, LEAF)
    d.ellipse(box(kx, ky, R(10), R(10)), fill=LEAF + (255,))
    sx, sy = T(418, 414)
    d.rounded_rectangle([s(sx - R(6)), s(sy - R(20)), s(sx + R(6)), s(sy + R(4))], radius=s(R(6)), fill=LEAF + (255,))


def gradient_square(radius):
    g = Image.new("RGBA", (N * SS, N * SS))
    gd = ImageDraw.Draw(g)
    for y in range(N * SS):
        t = y / (N * SS - 1)
        c = tuple(int(GREEN_TOP[i] * (1 - t) + GREEN_BOTTOM[i] * t) for i in range(3))
        gd.line([(0, y), (N * SS, y)], fill=c + (255,))
    m = mask(lambda m: m.rounded_rectangle([0, 0, N * SS - 1, N * SS - 1], radius=s(radius), fill=255))
    out = Image.new("RGBA", g.size, (0, 0, 0, 0))
    out.paste(g, (0, 0), m)
    return out


def finish(img):
    return img.resize((N, N), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)

    icon = gradient_square(230)
    draw_mark(icon)
    icon = finish(icon)
    icon.save(OUT / "icon.png")

    # Adaptive icon: Android masks to a circle/squircle inside a 66% safe zone.
    fg = Image.new("RGBA", (N * SS, N * SS), (0, 0, 0, 0))
    draw_mark(fg, scale=0.62)
    finish(fg).save(OUT / "icon_foreground.png")

    mark = Image.new("RGBA", (N * SS, N * SS), (0, 0, 0, 0))
    draw_mark(mark)
    finish(mark).save(OUT / "mark.png")

    prev = Image.new("RGB", (1024 + 512 + 256 + 128 + 64 + 6 * 24, 1024 + 48), (255, 255, 255))
    x = 24
    for size in (1024, 512, 256, 128, 64):
        prev.paste(icon.resize((size, size), Image.LANCZOS), (x, 24), icon.resize((size, size), Image.LANCZOS))
        x += size + 24
    prev.save(OUT / "logo_preview.png")
    print("wrote", sorted(p.name for p in OUT.iterdir()))


if __name__ == "__main__":
    main()
