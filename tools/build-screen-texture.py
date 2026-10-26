"""Generate the 512px idle projection screen: black with a white border."""
from pathlib import Path
import binascii
import struct
import zlib

SIZE = 512
BORDER = 22
TARGET = Path(__file__).resolve().parents[1] / 'common/media/textures/KBM_ProjectionScreen.png'


def chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', binascii.crc32(kind + data) & 0xffffffff)


def main() -> None:
    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)
        for x in range(SIZE):
            frame = x < BORDER or x >= SIZE - BORDER or y < BORDER or y >= SIZE - BORDER
            # Opaque idle pixels do not carry the playback shader's alpha marker.
            rows.extend((250, 250, 250, 255) if frame else (0, 0, 0, 255))
    data = (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', SIZE, SIZE, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b''))
    TARGET.write_bytes(data)
    print('Generated', TARGET)


if __name__ == '__main__':
    main()
