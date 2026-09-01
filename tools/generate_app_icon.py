from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "app_icon_master.png"
RES = ROOT / "android" / "app" / "src" / "main" / "res"
SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    for density, size in SIZES.items():
        target = RES / density
        target.mkdir(parents=True, exist_ok=True)
        icon = source.resize((size, size), Image.Resampling.LANCZOS)
        icon.save(target / "ic_launcher.png", format="PNG", optimize=True)
    print(f"Generated {len(SIZES)} Android launcher icon sizes from {SOURCE}")


if __name__ == "__main__":
    main()
