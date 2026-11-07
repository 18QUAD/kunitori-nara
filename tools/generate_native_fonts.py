"""Create native font weights from the bundled OFL variable font.

Development dependency: fonttools==4.61.1. The browser font is not modified.
"""
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = Path(__file__).resolve().parents[1]
for weight in (400, 500, 600, 700, 900):
    font = instantiateVariableFont(
        TTFont(ROOT / 'assets/fonts/NotoSansJP.ttf'), {'wght': weight},
        inplace=True, updateFontNames=True)
    assert 'fvar' not in font and font['OS/2'].usWeightClass == weight
    font.save(ROOT / f'assets/fonts/NotoSansJPNative-{weight}.ttf')
