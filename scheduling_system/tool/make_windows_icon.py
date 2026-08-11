"""Regenerate windows/runner/resources/app_icon.ico from app_icon_source.png.

Run after `dart run flutter_launcher_icons`, which overwrites the .ico with
a single 256x256 entry. Windows picks the nearest available entry and
scales it, so a 256-only icon is downscaled 256->16 on the fly for the
taskbar and Explorer's details view and comes out soft. This writes the
seven sizes the shell actually asks for, each resampled with LANCZOS
rather than left to the shell.

    python tool/make_windows_icon.py

Requires Pillow (`pip install pillow`). Nothing else in the project needs
it -- this is a build tool, not a runtime dependency, which is why it is
not in requirements.txt.

The source is app_icon_source.png beside this file, NOT
assets/logo/kaizen_logo.png: that asset is 1158x1358 with uneven
transparent margins, and squaring it by a plain resize turns the round
patch into an ellipse. The source here is that asset cropped to its alpha
bounding box (the badge is 1101x1102, square already) and padded to 1024.
Regenerate it with rebuild_source() below if the logo ever changes.
"""

from pathlib import Path

from PIL import Image

HERE = Path(__file__).parent
PROJECT = HERE.parent

SOURCE = HERE / "app_icon_source.png"
TARGET = PROJECT / "windows" / "runner" / "resources" / "app_icon.ico"
LOGO = PROJECT / "assets" / "logo" / "kaizen_logo.png"

# What the Windows shell requests: 16 in the details view, 32 on the
# taskbar, 48 in medium icons, 256 for extra-large. The rest are the
# in-between steps the shell picks for high-DPI displays.
SIZES = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]


def rebuild_source():
    """Rebuild app_icon_source.png from the logo asset. Only needed if the
    logo itself changes -- the committed source is already correct."""
    logo = Image.open(LOGO).convert("RGBA")
    cropped = logo.crop(logo.getbbox())
    w, h = cropped.size
    side = max(w, h)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(cropped, ((side - w) // 2, (side - h) // 2))
    canvas.resize((1024, 1024), Image.LANCZOS).save(SOURCE)
    print(f"rebuilt {SOURCE.relative_to(PROJECT)} from {LOGO.name}")


def main():
    src = Image.open(SOURCE).convert("RGBA")
    frames = [src.resize(s, Image.LANCZOS) for s in SIZES]
    # Pillow takes the largest as the base and the rest as append_images.
    frames[-1].save(TARGET, format="ICO", sizes=SIZES, append_images=frames[:-1])
    print(f"wrote {TARGET.relative_to(PROJECT)} with {len(SIZES)} sizes")
    print("rebuild the app for it to take effect: flutter build windows --release ...")


if __name__ == "__main__":
    main()
