#!/usr/bin/env python3
"""Create a basic photomosaic from a hero image and source-photo folder."""

from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image, ImageOps

EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff"}


def rgb_distance(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    """Return a cheap perceptually weighted RGB distance."""
    return math.sqrt(2 * (a[0] - b[0]) ** 2 + 4 * (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2)


def average_rgb(image: Image.Image) -> tuple[float, float, float]:
    pixel = image.convert("RGB").resize((1, 1), Image.Resampling.BOX).getpixel((0, 0))
    return tuple(float(value) for value in pixel)


def load_tiles(folder: Path, tile_size: tuple[int, int]) -> list[tuple[Path, Image.Image, tuple[float, float, float]]]:
    tiles = []
    for path in sorted(folder.rglob("*")):
        if path.is_file() and path.suffix.lower() in EXTENSIONS:
            try:
                with Image.open(path) as source:
                    oriented = ImageOps.exif_transpose(source).convert("RGB")
                    tile = ImageOps.fit(oriented, tile_size, Image.Resampling.LANCZOS)
                tiles.append((path, tile, average_rgb(tile)))
            except (OSError, ValueError):
                print(f"Skipping unreadable image: {path}")
    if not tiles:
        raise ValueError(f"No readable source images found in {folder}")
    return tiles


def choose_tile(target, tiles, recent: list[int], repeat_window: int) -> int:
    allowed = [index for index in range(len(tiles)) if index not in recent[-repeat_window:]]
    candidates = allowed or list(range(len(tiles)))
    return min(candidates, key=lambda index: rgb_distance(target, tiles[index][2]))


def generate(
    hero_path: Path,
    source_dir: Path,
    output_path: Path,
    columns: int = 50,
    tile_width: int = 32,
    repeat_window: int = 8,
    overlay: float = 0.16,
) -> dict[str, int]:
    if columns < 1 or tile_width < 1:
        raise ValueError("columns and tile-width must be positive")
    if repeat_window < 0:
        raise ValueError("repeat-window cannot be negative")
    if not 0 <= overlay <= 1:
        raise ValueError("overlay must be between 0 and 1")

    with Image.open(hero_path) as opened:
        hero = ImageOps.exif_transpose(opened).convert("RGB")

    rows = max(1, round(columns * hero.height / hero.width))
    tile_size = (tile_width, tile_width)
    target = ImageOps.fit(hero, (columns, rows), Image.Resampling.LANCZOS)
    tiles = load_tiles(source_dir, tile_size)
    canvas = Image.new("RGB", (columns * tile_width, rows * tile_width))
    recent: list[int] = []

    for row in range(rows):
        for column in range(columns):
            target_colour = tuple(float(value) for value in target.getpixel((column, row)))
            index = choose_tile(target_colour, tiles, recent, min(repeat_window, len(tiles) - 1))
            recent.append(index)
            tile = tiles[index][1]
            if overlay:
                tint = Image.new("RGB", tile_size, tuple(int(value) for value in target_colour))
                tile = Image.blend(tile, tint, overlay)
            canvas.paste(tile, (column * tile_width, row * tile_width))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    save_args = {"quality": 94, "subsampling": 0} if output_path.suffix.lower() in {".jpg", ".jpeg"} else {}
    canvas.save(output_path, **save_args)
    return {"columns": columns, "rows": rows, "tiles": len(tiles), "width": canvas.width, "height": canvas.height}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("hero", type=Path)
    parser.add_argument("sources", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--columns", type=int, default=50)
    parser.add_argument("--tile-width", type=int, default=32)
    parser.add_argument("--repeat-window", type=int, default=8)
    parser.add_argument("--overlay", type=float, default=0.16)
    args = parser.parse_args()
    try:
        stats = generate(args.hero, args.sources, args.output, args.columns, args.tile_width, args.repeat_window, args.overlay)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(
        f"Created {args.output} — {stats['columns']}x{stats['rows']} cells, "
        f"{stats['tiles']} source photos, {stats['width']}x{stats['height']} px"
    )


if __name__ == "__main__":
    main()

