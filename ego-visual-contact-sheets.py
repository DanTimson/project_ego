#!/usr/bin/env python3
"""Build a local Project EGO visual index and labeled preview sheets."""
import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageDraw


EXTRA_ARCHIVES = (
    "MapObj", "Flag", "Castle", "Resource", "OutBld", "OutBuild",
    "Site", "Illustration", "art",
)
GROUPS = {
    "menu": ("Interface", "Illustration", "art"),
    "province": ("MapObj", "Flag", "Resource", "Site"),
    "settlements": ("Castle", "OutBld", "OutBuild"),
    "tactical": ("Battlefield", "Units", "Unit_icons", "Ability", "Buttons"),
}


def extract_missing(dat_root, exports, grabber):
    for archive in EXTRA_ARCHIVES:
        destination = exports / archive
        if (destination / "manifest.json").is_file():
            continue
        source = dat_root / f"{archive}.dat"
        if not source.is_file():
            print(f"Missing: {source.name}", file=sys.stderr)
            continue
        with tempfile.TemporaryDirectory(prefix=".extract-", dir=exports) as work:
            candidate = Path(work) / archive
            result = subprocess.run([grabber, "extract", source, candidate])
            if result.returncode or not (candidate / "manifest.json").is_file():
                print(f"Skipped {source.name} after extraction error", file=sys.stderr)
                continue
            # Older extraction attempts may have left an empty destination.
            if destination.is_dir() and not any(destination.iterdir()):
                destination.rmdir()
            if destination.exists():
                print(f"Preserving incomplete export: {destination}", file=sys.stderr)
                continue
            shutil.move(candidate, destination)


def build_sheets(root, index):
    by_archive = defaultdict(list)
    for asset in index["assets"]:
        if asset["type"] == "image":
            by_archive[asset["archive"]].append(asset)

    output = root / "contact-sheets"
    output.mkdir(exist_ok=True)
    for group, archives in GROUPS.items():
        for archive in archives:
            rows = by_archive[archive]
            for start in range(0, len(rows), 48):
                page = rows[start:start + 48]
                sheet = Image.new("RGB", (960, ((len(page) + 5) // 6) * 116), "#20252b")
                draw = ImageDraw.Draw(sheet)
                for i, asset in enumerate(page):
                    x, y = (i % 6) * 160, (i // 6) * 116
                    label = "unreadable"
                    try:
                        with Image.open(root / asset["path"]) as source:
                            width, height = source.size
                            thumb = source.convert("RGB")
                            thumb.thumbnail((150, 82), Image.Resampling.NEAREST)
                        thumb.putdata([
                            (49, 56, 64) if pixel == (255, 0, 255) else pixel
                            for pixel in thumb.getdata()
                        ])
                        sheet.paste(thumb, (x + (160 - thumb.width) // 2, y + 3))
                        label = f"{width}x{height}"
                    except OSError as error:
                        print(f"{asset['key']}: {error}", file=sys.stderr)
                    draw.text((x + 5, y + 87), asset["source_id"][:24], fill="white")
                    draw.text((x + 5, y + 101), label, fill="#b8c6d4")
                sheet.save(output / f"{group}-{archive}-{start // 48 + 1:02}.png")
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--asset-root", type=Path, required=True)
    parser.add_argument("--dat-root", type=Path, required=True)
    parser.add_argument("--grabber", type=Path)
    args = parser.parse_args()
    repo = args.repo.resolve()
    root = args.asset_root.resolve()
    grabber = args.grabber or repo / ".local/tools/eador_dat"
    exports = root / "exports"
    prepare = repo / "tools/prepare_tactical_assets.py"
    for path in (exports, args.dat_root, grabber, prepare):
        if not path.exists():
            parser.error(f"Missing path: {path}")

    extract_missing(args.dat_root, exports, grabber.resolve())
    index_path = root / "visual-index.json"
    command = [sys.executable, prepare, "--output", index_path]
    for manifest in sorted(exports.glob("*/manifest.json")):
        command.extend(("--export", f"{manifest.parent.name}={manifest.parent}"))
    subprocess.run(command, check=True)
    output = build_sheets(root, json.loads(index_path.read_text(encoding="utf-8")))
    print(f"Combined index: {index_path}")
    print(f"Contact sheets: {output}")


if __name__ == "__main__":
    main()
