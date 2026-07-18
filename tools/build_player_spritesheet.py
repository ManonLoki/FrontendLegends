#!/usr/bin/env python3
"""Build the runtime player atlas from the two generated 4x4 RGBA sheets."""

from collections import deque
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "assets" / "Texture" / "player_sources"
OUTPUT_IMAGE = ROOT / "assets" / "Texture" / "player.png"
OUTPUT_DATA = ROOT / "assets" / "Texture" / "player.tpsheet"
FRAME_SIZE = (40, 48)
DIRECTIONS = ("down", "left", "right", "up")
CHARACTERS = (
    ("male", SOURCE_DIR / "rabbit_male_rgba.png"),
    ("female", SOURCE_DIR / "succubus_female_rgba.png"),
)


def cell_edges(length: int) -> list[int]:
    return [round(index * length / 4) for index in range(5)]


def main_component_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    """Ignore tiny pixels leaking in from an adjacent generated grid cell."""
    alpha = image.getchannel("A")
    width, height = image.size
    alpha_values = (
        alpha.get_flattened_data() if hasattr(alpha, "get_flattened_data") else alpha.getdata()
    )
    mask = bytearray(1 if value >= 128 else 0 for value in alpha_values)
    best: list[int] = []
    for start, opaque in enumerate(mask):
        if not opaque:
            continue
        queue = deque([start])
        mask[start] = 0
        component: list[int] = []
        while queue:
            position = queue.popleft()
            component.append(position)
            x = position % width
            y = position // width
            for neighbor in (
                position - 1 if x else -1,
                position + 1 if x + 1 < width else -1,
                position - width if y else -1,
                position + width if y + 1 < height else -1,
            ):
                if neighbor >= 0 and mask[neighbor]:
                    mask[neighbor] = 0
                    queue.append(neighbor)
        if len(component) > len(best):
            best = component
    if not best:
        raise ValueError("generated sprite cell contains no opaque subject")
    xs = [position % width for position in best]
    ys = [position // width for position in best]
    padding = 2
    return (
        max(0, min(xs) - padding),
        max(0, min(ys) - padding),
        min(width, max(xs) + padding + 1),
        min(height, max(ys) + padding + 1),
    )


def extract_frames(source: Image.Image) -> list[Image.Image]:
    x_edges = cell_edges(source.width)
    y_edges = cell_edges(source.height)
    frames: list[Image.Image] = []
    for row in range(4):
        for column in range(4):
            cell = source.crop(
                (x_edges[column], y_edges[row], x_edges[column + 1], y_edges[row + 1])
            )
            frames.append(cell.crop(main_component_bbox(cell)))
    return frames


def normalize_frames(frames: list[Image.Image]) -> list[Image.Image]:
    max_width = max(frame.width for frame in frames)
    max_height = max(frame.height for frame in frames)
    scale = min((FRAME_SIZE[0] - 4) / max_width, (FRAME_SIZE[1] - 4) / max_height)
    normalized: list[Image.Image] = []
    for frame in frames:
        size = (max(1, round(frame.width * scale)), max(1, round(frame.height * scale)))
        sprite = frame.resize(size, Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", FRAME_SIZE)
        position = ((FRAME_SIZE[0] - size[0]) // 2, FRAME_SIZE[1] - size[1] - 2)
        canvas.alpha_composite(sprite, position)
        normalized.append(canvas)
    return normalized


def build() -> None:
    atlas = Image.new("RGBA", (FRAME_SIZE[0] * 4, FRAME_SIZE[1] * 8))
    sprites: list[dict[str, object]] = []
    for character_index, (gender, source_path) in enumerate(CHARACTERS):
        source = Image.open(source_path).convert("RGBA")
        frames = normalize_frames(extract_frames(source))
        for direction_index, direction in enumerate(DIRECTIONS):
            atlas_row = character_index * 4 + direction_index
            for frame_index in range(4):
                x = frame_index * FRAME_SIZE[0]
                y = atlas_row * FRAME_SIZE[1]
                atlas.alpha_composite(frames[direction_index * 4 + frame_index], (x, y))
                region = {"x": x, "y": y, "w": FRAME_SIZE[0], "h": FRAME_SIZE[1]}
                for motion in ("idle", "run"):
                    sprites.append(
                        {
                            "filename": f"player_{gender}_{direction}_{motion}_{frame_index}.png",
                            "region": region.copy(),
                            "margin": {"x": 0, "y": 0, "w": 0, "h": 0},
                        }
                    )
    atlas.save(OUTPUT_IMAGE, optimize=True)
    data = {
        "textures": [
            {
                "image": OUTPUT_IMAGE.name,
                "size": {"w": atlas.width, "h": atlas.height},
                "sprites": sprites,
            }
        ]
    }
    OUTPUT_DATA.write_text(json.dumps(data, ensure_ascii=False, indent="\t") + "\n")


if __name__ == "__main__":
    build()
