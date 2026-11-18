# 生成手写体子集：GB2312 + 常用标点 + ASCII，从 tools/fonts 的完整字体重建。
# 用法：python harmony/NuanlinHarmony/tools/subset-font.py
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.subset import Options, Subsetter

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "tools" / "fonts" / "JournalHandwriting-full.ttf"
TARGET = ROOT / "entry" / "src" / "main" / "resources" / "rawfile" / "JournalHandwriting.ttf"


def gb2312_chars() -> set[str]:
    chars: set[str] = set()
    for high in range(0xA1, 0xF8):
        for low in range(0xA1, 0xFF):
            try:
                chars.add(bytes([high, low]).decode("gb2312"))
            except UnicodeDecodeError:
                continue
    return chars


def main() -> None:
    chars = gb2312_chars()
    chars.update(chr(cp) for cp in range(0x20, 0x7F))
    chars.update(chr(cp) for cp in range(0x3000, 0x3040))
    chars.update(chr(cp) for cp in range(0xFF00, 0xFFF0))

    options = Options()
    options.name_IDs = ["*"]
    options.notdef_outline = True
    options.recalc_bounds = True

    font = TTFont(SOURCE)
    subsetter = Subsetter(options=options)
    subsetter.populate(unicodes=[ord(char) for char in chars])
    subsetter.subset(font)
    font.save(TARGET)
    print(f"chars={len(chars)} glyphs={font['maxp'].numGlyphs} "
          f"size={TARGET.stat().st_size / 1024 / 1024:.2f}MB")


if __name__ == "__main__":
    main()
