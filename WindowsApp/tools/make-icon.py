#!/usr/bin/env python3
"""Draws app.ico (a study-green football badge) without any image libraries."""
import math
import struct
import zlib
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "src" / "StudyManagerFC.Desktop" / "app.ico"
SIZES = [16, 24, 32, 48, 64, 128, 256]
SS = 4  # supersampling factor

GREEN = (47, 191, 113)
TEAL = (31, 168, 160)
INK = (18, 32, 27)
WHITE = (255, 255, 255)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def rounded_rect_sdf(x, y, w, h, r):
    dx = abs(x - w / 2) - (w / 2 - r)
    dy = abs(y - h / 2) - (h / 2 - r)
    ax, ay = max(dx, 0.0), max(dy, 0.0)
    return math.hypot(ax, ay) + min(max(dx, dy), 0.0) - r


def pentagon_vertices(cx, cy, radius, rotation=-math.pi / 2):
    return [
        (cx + radius * math.cos(rotation + i * 2 * math.pi / 5),
         cy + radius * math.sin(rotation + i * 2 * math.pi / 5))
        for i in range(5)
    ]


def inside_polygon(px, py, points):
    inside = False
    j = len(points) - 1
    for i in range(len(points)):
        xi, yi = points[i]
        xj, yj = points[j]
        if (yi > py) != (yj > py):
            if px < (xj - xi) * (py - yi) / (yj - yi) + xi:
                inside = not inside
        j = i
    return inside


def distance_to_segment(px, py, ax, ay, bx, by):
    abx, aby = bx - ax, by - ay
    length = abx * abx + aby * aby
    if length == 0:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * abx + (py - ay) * aby) / length))
    return math.hypot(px - (ax + t * abx), py - (ay + t * aby))


def sample(size, x, y):
    """Returns RGBA for a point in a size x size image."""
    w = h = size
    radius = size * 0.225
    if rounded_rect_sdf(x, y, w, h, radius) > 0:
        return (0, 0, 0, 0)

    t = y / max(1, size - 1)
    base = lerp(GREEN, TEAL, t)

    cx = cy = size / 2
    ball = size * 0.315
    distance = math.hypot(x - cx, y - cy)

    # thin light ring just outside the ball
    if abs(distance - ball * 1.09) < size * 0.018:
        return (255, 255, 255, 110)

    if distance > ball:
        return (*base, 255)

    if distance > ball - size * 0.012:
        return (235, 245, 240, 255)

    # ball patches
    pentagon = pentagon_vertices(cx, cy, ball * 0.40)
    if inside_polygon(x, y, pentagon):
        return (*INK, 255)

    for vx, vy in pentagon:
        angle = math.atan2(vy - cy, vx - cx)
        ax = cx + math.cos(angle) * ball * 0.40
        ay = cy + math.sin(angle) * ball * 0.40
        bx = cx + math.cos(angle) * ball * 0.86
        by = cy + math.sin(angle) * ball * 0.86
        if distance_to_segment(x, y, ax, ay, bx, by) < size * 0.022:
            return (*INK, 255)

    return (255, 255, 255, 255)


def render(size):
    pixels = []
    step = 1.0 / SS
    for y in range(size):
        row = bytearray()
        for x in range(size):
            r = g = b = a = 0
            for sy in range(SS):
                for sx in range(SS):
                    pr, pg, pb, pa = sample(size, x + (sx + 0.5) * step, y + (sy + 0.5) * step)
                    r += pr * pa
                    g += pg * pa
                    b += pb * pa
                    a += pa
            count = SS * SS
            if a == 0:
                row.extend(bytes((0, 0, 0, 0)))
            else:
                row.extend(bytes((r // a, g // a, b // a, a // count)))
        pixels.append(bytes(row))
    return pixels


def png_bytes(size):
    rows = render(size)
    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


def main():
    images = [(size, png_bytes(size)) for size in SIZES]
    header = struct.pack("<HHH", 0, 1, len(images))
    directory = b""
    offset = 6 + 16 * len(images)
    payload = b""
    for size, data in images:
        directory += struct.pack(
            "<BBBBHHII",
            0 if size >= 256 else size,
            0 if size >= 256 else size,
            0, 0, 1, 32, len(data), offset)
        payload += data
        offset += len(data)
    OUT.write_bytes(header + directory + payload)
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
