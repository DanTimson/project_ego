#!/usr/bin/env python3
"""Capture CX-032 Home/catalogue at minimum size in local, fallback and partial modes.

Use on a real WSL rendering display after the normal Godot gate. Artwork,
mappings, logs and screenshots remain inside the supplied private asset root.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess

REPO = Path(__file__).resolve().parents[1]
SCREENS = ('home-opening', 'catalogue-opening', 'catalogue-built-available-locked',
           'catalogue-scrolled', 'home-built')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--asset-root', type=Path, required=True)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', 'godot'))
    parser.add_argument('--index-name', default='visual-index.json')
    parser.add_argument('--mapping-name', default='cx032-mapping.json')
    args = parser.parse_args()
    root = args.asset_root.resolve(strict=True)
    for name in (args.index_name, args.mapping_name):
        if Path(name).name != name:
            parser.error('index and mapping must be filenames inside the asset root')
    mapping = json.loads((root / args.mapping_name).read_text())
    partial = {key: value if key == 'version' else {'content': [], 'instances': []}
               if isinstance(value, dict) else [] for key, value in mapping.items()}
    partial['ui'] = [item for item in mapping['ui'] if item['id'] == 'castle_market']
    partial_path = root / 'cx032-partial-mapping.json'
    partial_path.write_text(json.dumps(partial, indent=2) + '\n')
    output = root / 'captures-cx032'
    output.mkdir(exist_ok=True)
    records = []
    for mode in ('local', 'fallback', 'partial'):
        env = dict(os.environ)
        env['EGO_ASSET_INDEX'] = str(root / args.index_name if mode != 'fallback'
                                     else root / 'cx032-absent-index.json')
        env['EGO_ASSET_MAPPING'] = str(partial_path if mode == 'partial'
                                       else root / args.mapping_name)
        command = [args.godot, '--path', str(REPO), '--audio-driver', 'Dummy', '--script',
                   'tools/capture_castle_review.gd', '--', str(output), mode]
        try:
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=60)
            log = result.stdout + result.stderr
            passed = (result.returncode == 0 and 'ERROR:' not in log
                      and log.count('error=0') == len(SCREENS) and all(
                          (output / f'{mode}-{name}-960x540.png').is_file() for name in SCREENS))
        except subprocess.TimeoutExpired as error:
            log = f'Rendering capture timed out: {error}'
            passed = False
        (output / f'{mode}.log').write_text(log)
        records.append({'mode': mode, 'passed': passed})
        print(f'{mode}: {"PASS" if passed else "BLOCKED/FAIL"} ({output / (mode + ".log")})',
              flush=True)
    (output / 'results.json').write_text(json.dumps(records, indent=2) + '\n')
    return 0 if all(record['passed'] for record in records) else 1


if __name__ == '__main__':
    raise SystemExit(main())
