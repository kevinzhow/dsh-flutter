"""Synthetic PNG fixtures for the extension builders (no real content: generated pixels only).

`png_data_url` / `png_base64` return the same bytes for both providers: the builder puts the base64 text into the case
props, the React host uses it in a data URL, the Flutter case decodes it. Image sizes are chosen by the callers so that
the browser and Flutter map source pixels 1:1 (no resampling): the natural size in device pixels equals the displayed
CSS size times the case's density.
"""
import base64
import struct
import zlib


def _chunk(kind, data):
    body = kind + data
    return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body) & 0xffffffff)


def png_bytes(width, height, pixel):
    """RGB PNG from `pixel(x, y) -> (r, g, b)`."""
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            rows.extend(pixel(x, y))
    return (b'\x89PNG\r\n\x1a\n' + _chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
            + _chunk(b'IDAT', zlib.compress(bytes(rows), 9)) + _chunk(b'IEND', b''))


def _mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def scene(width, height, top=(88, 140, 210), bottom=(238, 170, 96), accent=(255, 255, 255)):
    """A smooth vertical gradient with a diagonal band, a crosshair through the centre and distinct corner blocks:
    a shifted, cropped or scaled copy is visible in a pixel diff."""
    block = max(4, min(width, height) // 8)
    corners = {(0, 0): (214, 66, 66), (1, 0): (60, 160, 90), (0, 1): (64, 80, 200), (1, 1): (240, 200, 60)}

    def pixel(x, y):
        for (cx, cy), color in corners.items():
            x0 = 0 if cx == 0 else width - block
            y0 = 0 if cy == 0 else height - block
            if x0 <= x < x0 + block and y0 <= y < y0 + block:
                return color
        if abs(x - width // 2) < 1 or abs(y - height // 2) < 1:
            return accent
        base = _mix(top, bottom, y / max(1, height - 1))
        band = (x * height - y * width) / max(1, width * height)
        if abs(band) < 0.06:
            return _mix(base, accent, 0.35)
        return base
    return png_bytes(width, height, pixel)


def png_base64(data):
    return base64.b64encode(data).decode('ascii')
