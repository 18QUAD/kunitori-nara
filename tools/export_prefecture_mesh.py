"""Export the shared national border network for constant-width image caching.

Run prefecture_border_mesh.py first. Coordinates retain micodegree precision;
shared edges are stored once, exactly as in the existing national border tiles.
"""
from pathlib import Path
import struct
import shapely

ROOT = Path(__file__).resolve().parents[1]


def export(source, target):
    lines = list(shapely.from_wkb(source.read_bytes()).geoms)
    output = bytearray(b'KBR1' + struct.pack('<I', len(lines)))
    for line in lines:
        coordinates = list(line.coords)
        output.extend(struct.pack('<4fI', *line.bounds, len(coordinates)))
        for x, y in coordinates:
            output.extend(struct.pack('<ii', round(x * 1000000), round(y * 1000000)))
    target.write_bytes(output)
    print(len(lines), 'shared lines;', len(output), 'bytes')


if __name__ == '__main__':
    export(ROOT / 'data/raw/shared_prefectures/network.wkb',
           ROOT / 'assets/data/prefecture_border_mesh.bin')
