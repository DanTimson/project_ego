#!/usr/bin/env python3
"""Capture the frozen presentation and working patch into the private asset root.

Requires a real Godot 4.3 rendering display. Does not stage, commit, export or
create a worktree. Baseline sources are a temporary git archive, never a checkout.
"""
import argparse
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile

BASE = '0ce88811bdfcf0c699cdcf5c2ba9781482b8bd8f'
REPO = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--asset-root', type=Path, required=True)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', 'godot'))
    parser.add_argument('--index-name', default='visual-index.json')
    parser.add_argument('--mapping-name', default='cx029-mapping.json')
    parser.add_argument('--baseline', default=BASE)
    args = parser.parse_args()
    root = args.asset_root.resolve(strict=True)
    output = root / 'captures'
    output.mkdir(exist_ok=True)
    for name in (args.index_name, args.mapping_name):
        if Path(name).name != name:
            parser.error('index and mapping names must be filenames')
    mapping = json.loads((root / args.mapping_name).read_text())
    partial = {k: v if k == 'version' else {'content': [], 'instances': []}
               if isinstance(v, dict) else [] for k, v in mapping.items()}
    partial['units']['content'] = mapping['units']['content'][:1]
    partial_path = root / 'cx029-partial-mapping.json'
    partial_path.write_text(json.dumps(partial, indent=2) + '\n')
    records = []

    def run(project, phase, mode):
        env = dict(os.environ)
        env['EGO_ASSET_INDEX'] = str(root / args.index_name) if mode != 'fallback' else str(root / 'absent-index.json')
        env['EGO_ASSET_MAPPING'] = str(partial_path if mode == 'partial' else root / args.mapping_name)
        command = [args.godot, '--path', str(project), '--audio-driver', 'Dummy', '--script',
                   str(REPO / 'tools/capture_presentation.gd'), '--', str(output), f'{phase}-{mode}']
        result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=120)
        log = result.stdout + result.stderr
        path = output / f'{phase}-{mode}.log'
        path.write_text(log)
        expected = [f'{phase}-{mode}-{screen}-{w}x{h}.png'
                    for screen in ('menu', 'map', 'home', 'battle')
                    for w, h in ((960, 540), (1152, 648), (1440, 810))]
        passed = (result.returncode == 0 and 'ERROR:' not in log
                  and log.count('CAPTURE ') == len(expected)
                  and log.count('error=0') == len(expected) and all(
            (output / name).is_file() for name in expected))
        records.append({'phase': phase, 'mode': mode, 'passed': passed,
                        'log': str(path), 'expected': expected})
        print(f'{phase}-{mode}: {"PASS" if passed else "BLOCKED/FAIL"} ({path})')

    # Prepare the baseline without writing any VCS state.
    with tempfile.TemporaryDirectory(prefix='cx029-baseline-', dir=root) as temp:
        baseline = Path(temp)
        archive = subprocess.run(['git', 'archive', args.baseline], cwd=REPO,
                                 check=True, capture_output=True).stdout
        with tarfile.open(fileobj=io.BytesIO(archive)) as stream:
            stream.extractall(baseline, filter='data')
        scan = subprocess.run([args.godot, '--headless', '--path', str(baseline),
                               '--editor', '--quit'], capture_output=True, text=True, timeout=120)
        (output / 'baseline-import.log').write_text(scan.stdout + scan.stderr)
        for mode in ('local', 'fallback'):
            run(baseline, 'before', mode)
    for mode in ('local', 'fallback', 'partial'):
        run(REPO, 'after', mode)
    (output / 'capture-results.json').write_text(json.dumps(records, indent=2) + '\n')
    return 0 if all(record['passed'] for record in records) else 1


if __name__ == '__main__':
    raise SystemExit(main())
