from pathlib import Path
import tempfile
import unittest

from PIL import Image

from prototype.mosaic import average_rgb, choose_tile, generate, rgb_distance


class MosaicTests(unittest.TestCase):
    def test_rgb_distance_is_zero_for_identical_colours(self) -> None:
        self.assertEqual(rgb_distance((10, 20, 30), (10, 20, 30)), 0)

    def test_average_rgb_for_solid_image(self) -> None:
        self.assertEqual(average_rgb(Image.new("RGB", (4, 4), (12, 34, 56))), (12.0, 34.0, 56.0))

    def test_choose_tile_respects_recent_window(self) -> None:
        tiles = [
            (Path("dark.jpg"), Image.new("RGB", (1, 1)), (0.0, 0.0, 0.0)),
            (Path("light.jpg"), Image.new("RGB", (1, 1)), (255.0, 255.0, 255.0)),
        ]
        self.assertEqual(choose_tile((0, 0, 0), tiles, recent=[0], repeat_window=1), 1)

    def test_generate_creates_expected_dimensions(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            hero = root / "hero.png"
            sources = root / "sources"
            output = root / "result.png"
            sources.mkdir()
            Image.new("RGB", (8, 4), (200, 20, 20)).save(hero)
            Image.new("RGB", (5, 7), (200, 20, 20)).save(sources / "red.png")
            Image.new("RGB", (5, 7), (20, 20, 200)).save(sources / "blue.png")

            stats = generate(hero, sources, output, columns=4, tile_width=10, repeat_window=1, overlay=0)

            self.assertEqual(stats, {"columns": 4, "rows": 2, "tiles": 2, "width": 40, "height": 20})
            with Image.open(output) as rendered:
                self.assertEqual(rendered.size, (40, 20))

    def test_generate_rejects_invalid_overlay(self) -> None:
        for overlay in (-0.1, 1.1):
            with self.subTest(overlay=overlay), self.assertRaisesRegex(ValueError, "overlay"):
                generate(Path("hero.png"), Path("."), Path("out.png"), overlay=overlay)


if __name__ == "__main__":
    unittest.main()
