#!/usr/bin/env python3
"""Sort wallpaper files by their representative color, with a local cache."""

from __future__ import annotations

import colorsys
import json
import os
import subprocess
import sys
import tempfile
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageOps


VIDEO_EXTENSIONS = {
    ".mp4", ".mkv", ".webm", ".avi", ".mov", ".flv", ".wmv", ".m4v"
}
SAMPLE_SIZE = (32, 32)


def read_cache(cache_path: Path) -> dict:
    try:
        with cache_path.open("r", encoding="utf-8") as cache_file:
            value = json.load(cache_file)
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def extract_video_frame(path: str) -> Image.Image | None:
    for seek_time in ("1", "0"):
        command = [
            "ffmpeg", "-v", "error", "-threads", "1", "-ss", seek_time,
            "-i", path, "-an", "-sn", "-dn", "-frames:v", "1",
            "-vf", "scale=64:64:force_original_aspect_ratio=decrease:flags=area",
            "-c:v", "png", "-f", "image2pipe", "pipe:1",
        ]
        try:
            result = subprocess.run(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                timeout=12,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            continue
        if result.returncode == 0 and result.stdout:
            try:
                return Image.open(BytesIO(result.stdout)).convert("RGB")
            except Exception:
                pass
    return None


def sample_image(path: str, is_video: bool) -> Image.Image | None:
    if is_video:
        return extract_video_frame(path)

    try:
        with Image.open(path) as source:
            source.seek(0)
            image = ImageOps.exif_transpose(source).convert("RGBA")
            background = Image.new("RGBA", image.size, (0, 0, 0, 255))
            return Image.alpha_composite(background, image).convert("RGB")
    except Exception:
        # Pillow does not support every format; ffmpeg can decode several more.
        return extract_video_frame(path)


def representative_color(image: Image.Image | None) -> tuple[int, float, float]:
    if image is None:
        return (0, 0.0, 0.0)

    image = image.convert("RGB").resize(SAMPLE_SIZE, Image.Resampling.BOX)
    hue_bins = [0.0] * 36
    brightness_total = 0.0
    chroma_total = 0.0
    pixels = list(image.getdata())

    for red, green, blue in pixels:
        hue, saturation, value = colorsys.rgb_to_hsv(red / 255, green / 255, blue / 255)
        brightness_total += 0.2126 * red / 255 + 0.7152 * green / 255 + 0.0722 * blue / 255
        if saturation > 0.16 and value > 0.06:
            weight = saturation * value
            hue_bins[min(35, int(hue * 36))] += weight
            chroma_total += weight

    brightness = brightness_total / max(1, len(pixels))
    if chroma_total < len(pixels) * 0.04:
        # Put grayscale wallpapers first, from darker to lighter.
        return (0, 0.0, brightness)

    dominant_hue_bin = max(range(len(hue_bins)), key=hue_bins.__getitem__)
    return (1, (dominant_hue_bin + 0.5) / len(hue_bins), brightness)


def main() -> int:
    try:
        separator = sys.argv.index("--")
        cache_index = sys.argv.index("--cache")
        cache_path = Path(sys.argv[cache_index + 1])
        paths = sys.argv[separator + 1 :]
    except (ValueError, IndexError):
        return 2

    cache = read_cache(cache_path)
    entries = []
    seen = set()

    for original_index, path in enumerate(paths):
        if not path or path in seen:
            continue
        seen.add(path)
        extension = Path(path).suffix.lower()
        is_video = extension in VIDEO_EXTENSIONS

        try:
            stat = os.stat(path)
            cached = cache.get(path)
            if (isinstance(cached, dict)
                    and cached.get("size") == stat.st_size
                    and cached.get("mtime_ns") == stat.st_mtime_ns
                    and isinstance(cached.get("key"), list)
                    and len(cached["key"]) == 3):
                key = cached["key"]
            else:
                key = list(representative_color(sample_image(path, is_video)))
                cache[path] = {"size": stat.st_size, "mtime_ns": stat.st_mtime_ns, "key": key}
        except OSError:
            cache.pop(path, None)
            continue

        entries.append((tuple(key), original_index, path))

    entries.sort(key=lambda item: (item[0][0], item[0][1], item[0][2], item[1]))

    try:
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            "w", encoding="utf-8", dir=cache_path.parent,
            prefix=cache_path.name + ".", suffix=".tmp", delete=False,
        ) as cache_file:
            json.dump(cache, cache_file, ensure_ascii=False, separators=(",", ":"))
            temporary_path = Path(cache_file.name)
        os.replace(temporary_path, cache_path)
    except OSError:
        pass

    print(json.dumps([entry[2] for entry in entries], ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
