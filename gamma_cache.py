#!/usr/bin/env python3
"""Create a cached gamma-corrected wallpaper without changing its source."""

from __future__ import annotations

import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main() -> int:
    if len(sys.argv) < 4:
        print("usage: gamma_cache.py CACHE_DIR IMAGE_PATH GAMMA [ACTIVE_CACHE_PATH ...]", file=sys.stderr)
        return 2

    cache_dir = Path(sys.argv[1]).expanduser()
    source = Path(sys.argv[2]).expanduser()
    keep_paths = set(sys.argv[4:])
    try:
        gamma = float(sys.argv[3])
    except ValueError:
        print("invalid gamma value", file=sys.stderr)
        return 2

    if not source.is_file():
        print(f"image does not exist: {source}", file=sys.stderr)
        return 1
    if not 0.25 <= gamma <= 2.0:
        print("gamma must be between 0.25 and 2.00", file=sys.stderr)
        return 2

    try:
        cache_dir.mkdir(parents=True, exist_ok=True)
        identity = hashlib.sha256(os.fsencode(str(source))).hexdigest()[:24]
        value = f"{gamma:.2f}"
        extension = ".png"
        output = cache_dir / f"{identity}_gamma_{value}{extension}"
        source_mtime = source.stat().st_mtime_ns

        def prune_old_outputs() -> None:
            recent_kept = 0
            cached_files = sorted(
                cache_dir.glob(f"{identity}_gamma_*"),
                key=lambda path: path.stat().st_mtime_ns,
                reverse=True,
            )
            for cached in cached_files:
                if cached == output or str(cached) in keep_paths:
                    continue
                if cached.stat().st_mtime_ns >= source_mtime and recent_kept < 3:
                    recent_kept += 1
                else:
                    cached.unlink(missing_ok=True)

        if output.is_file() and output.stat().st_mtime_ns >= source_mtime:
            prune_old_outputs()
            print(output)
            return 0

        fd, temporary_name = tempfile.mkstemp(
            prefix=f".{identity}_gamma_{value}_", suffix=extension, dir=cache_dir
        )
        os.close(fd)
        temporary = Path(temporary_name)
        temporary.unlink()
        try:
            command = ["magick", f"{source}[0]", "-auto-orient", "-gamma", value]
            # Keep cache output lossless but avoid ImageMagick's slowest PNG encoding.
            command.extend(["-define", "png:compression-level=1", "-define", "png:compression-filter=0"])
            command.append(str(temporary))
            result = subprocess.run(
                command,
                check=False,
                capture_output=True,
                text=True,
            )
            if result.returncode != 0:
                print(result.stderr.strip() or "ImageMagick failed", file=sys.stderr)
                return result.returncode or 1
            os.replace(temporary, output)
            prune_old_outputs()
        finally:
            temporary.unlink(missing_ok=True)

        print(output)
        return 0
    except OSError as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
