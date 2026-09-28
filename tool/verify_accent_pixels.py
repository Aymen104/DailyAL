#!/usr/bin/env python3
"""Verify the AnimeX accent colours off the rendered bitmap, not the widget tree.

test/animex_render_test.dart proves the accent bar is in the tree with the
colour accentOf returned. That is necessary but not sufficient: nothing there
stops the bar being clipped, painted behind something, or drawn a fraction of
its intended height. This reads the actual pixels.

Dependency free on purpose - a hand-rolled PNG reader over zlib, which is in the
standard library, so this runs on a bare CI runner with no pip install and no
PIL. It asserts that each card shows one thin horizontal band of its expected
colour, and that no such band is grey.

Usage:  python3 tool/verify_accent_pixels.py test_output/animex_cards.png
"""

import sys
import zlib
import struct
from collections import Counter

# Must match test/animex_render_test.dart: the ids under test, in column order.
EXPECTED = [
    (9253, (0xFF, 0xD6, 0xAE)),   # dataset pale peach, low saturation
    (21,   (0xE4, 0x93, 0x35)),   # dataset orange; the only card with showTime
    (36055, None),                # no colour in the dataset -> derived hue
    (1,    (0xF1, 0x6B, 0x50)),   # dataset red
]
# Accent bar is 3 logical px at pixelRatio 2, and the grid sits inside 8pt of
# padding in a 900pt-wide surface, so the band starts here in device pixels.
EXPECTED_BAR_Y = 660
EXPECTED_BAR_H = 6
MIN_SATURATION = 0.20
GRID_PAD = 16      # 8 logical px of padding, doubled
CARD_W = 442       # 221 logical px per column, doubled


def card_span(col):
    """Device-pixel x range of card [col]. 8pt pad + 221pt columns, doubled."""
    x0 = GRID_PAD + CARD_W * col
    return x0, x0 + CARD_W


def read_png(path):
    """Minimal PNG reader: 8-bit RGB or RGBA, non-interlaced."""
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")

    pos, idat, meta = 8, bytearray(), None
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        ctype = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if ctype == b"IHDR":
            w, h, depth, ctype_, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8 or ctype_ not in (2, 6) or interlace != 0:
                raise ValueError(
                    f"unsupported PNG: depth={depth} colour={ctype_} "
                    f"interlace={interlace}"
                )
            meta = (w, h, 4 if ctype_ == 6 else 3)
        elif ctype == b"IDAT":
            idat += body
        elif ctype == b"IEND":
            break
        pos += 12 + length

    if meta is None:
        raise ValueError("no IHDR")

    w, h, channels = meta
    raw = zlib.decompress(bytes(idat))
    stride = w * channels
    out = bytearray(stride * h)

    prev = bytearray(stride)
    src = 0
    for y in range(h):
        ftype = raw[src]
        src += 1
        line = bytearray(raw[src:src + stride])
        src += stride
        # Undo the per-scanline PNG filter.
        if ftype == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif ftype == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        elif ftype != 0:
            raise ValueError(f"bad filter type {ftype} on row {y}")
        out[y * stride:(y + 1) * stride] = line
        prev = line

    return w, h, channels, bytes(out)


def px(buf, w, ch, x, y):
    i = (y * w + x) * ch
    return (buf[i], buf[i + 1], buf[i + 2])


def saturation(rgb):
    hi, lo = max(rgb), min(rgb)
    return 0.0 if hi == 0 else (hi - lo) / hi


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "test_output/animex_cards.png"
    w, h, ch, buf = read_png(path)
    print(f"{path}: {w}x{h}, {ch} channels/px")

    failures = []
    for col, (mal_id, expect) in enumerate(EXPECTED):
        x0, x1 = card_span(col)
        if x1 > w:
            failures.append(f"col {col}: card span {x0}-{x1} outside a {w}px image")
            continue

        # The bar must be the SAME colour across the card's own width, at the
        # expected height. Restricting to the card matters: a global
        # most-common over the whole row just returns whichever bar is
        # largest, and every column then reports the same colour.
        y = EXPECTED_BAR_Y
        row = Counter(px(buf, w, ch, xx, y) for xx in range(x0, x1))
        bar, count = row.most_common(1)[0]
        span = count

        # Measure the bar's thickness at the card's horizontal centre, well
        # clear of the corners. The bar is wrapped in a ClipRRect with a 6pt
        # radius, so the rounded corners legitimately shorten it in x and vary
        # the pixel count on the first and last rows; down the middle the
        # colour is uniform, which is what makes this an exact measurement.
        cx = (x0 + x1) // 2
        top, bottom = None, None
        for yy in range(EXPECTED_BAR_Y - 10, EXPECTED_BAR_Y + 20):
            if px(buf, w, ch, cx, yy) == bar:
                if top is None:
                    top = yy
                bottom = yy
        thickness = 0 if top is None else bottom - top + 1
        starts_right = (top == EXPECTED_BAR_Y)

        sat = saturation(bar)
        tag = f"mal {mal_id}"
        detail = f"  {tag:<10} #{bar[0]:02X}{bar[1]:02X}{bar[2]:02X} " \
                 f"span={span}/{CARD_W}px thick={thickness}/{EXPECTED_BAR_H}px " \
                 f"sat={sat:.2f}"

        # 6pt corner radius x2, doubled for the device pixel ratio, costs about
        # 26px of the 442. Anything short of that is not corner rounding.
        if span < CARD_W - 40:
            failures.append(f"{tag}: band does not span the card "
                            f"({span}/{CARD_W}px)")
            detail += "  FAIL narrow"
        elif not starts_right or thickness != EXPECTED_BAR_H:
            failures.append(f"{tag}: bar is {thickness}px thick at y={top}, "
                            f"want {EXPECTED_BAR_H}px at y={EXPECTED_BAR_Y}")
            detail += "  FAIL geometry"
        elif sat < MIN_SATURATION:
            # This is the assertion that matters most. A grey bar would be
            # indistinguishable from a missing one, which is exactly the
            # coverage hole the derived colour exists to close.
            failures.append(f"{tag}: band is grey (sat={sat:.2f})")
            detail += "  FAIL grey"
        elif expect is not None and bar != expect:
            failures.append(f"{tag}: got #{bar[0]:02X}{bar[1]:02X}{bar[2]:02X}, "
                            f"want #{expect[0]:02X}{expect[1]:02X}{expect[2]:02X}")
            detail += "  FAIL colour"
        else:
            detail += "  ok"
        print(detail)

    # Derived-colour card: hue must be the one the formula predicts. This is
    # what proves accentOf's fallback is a real function of the id rather than
    # an arbitrary colour that happens to be non-grey.
    dx0, dx1 = card_span(2)
    rgb = px(buf, w, ch, (dx0 + dx1) // 2, EXPECTED_BAR_Y)
    hi, lo = max(rgb), min(rgb)
    if hi == lo:
        print("derived hue: undefined (grey)")
        failures.append("derived hue undefined")
    else:
        if rgb[1] == hi:
            hue = 60 * (2 + (rgb[2] - rgb[0]) / (hi - lo))
        elif rgb[2] == hi:
            hue = 60 * (4 + (rgb[0] - rgb[1]) / (hi - lo))
        else:
            hue = 60 * (((rgb[1] - rgb[2]) / (hi - lo)) % 6)
        hue %= 360
        want = (36055 * 47) % 360
        delta = min(abs(hue - want), 360 - abs(hue - want))
        ok = delta < 6
        print(f"derived hue: {hue:.1f} deg, predicted {want} deg "
              f"(delta {delta:.1f})  {'ok' if ok else 'FAIL'}")
        if not ok:
            failures.append(f"derived hue {hue:.1f} != predicted {want}")

    if failures:
        print("\nFAILED:")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("\nAll accent bands verified in the rendered pixels.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
