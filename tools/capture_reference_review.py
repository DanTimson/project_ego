#!/usr/bin/env python3
"""Capture CX-031 before/after stills and geometry into the existing private root.

Archives the frozen base into temporary sources; never changes VCS state.
--rehearse writes measurements and logs only, without claiming rendered media.
"""
import argparse
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile

BASE = 'baa2c6393778dba27e2a6c9999f8be84ce6a126d'
REPO = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--asset-root', type=Path, required=True)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', 'godot'))
    parser.add_argument('--rehearse', action='store_true')
    args = parser.parse_args()
    asset_root = args.asset_root.resolve(strict=True)
    output = asset_root / 'captures' / 'cx031'
    output.mkdir(parents=True, exist_ok=True)
    # Regenerate only this task's mapping; keep accepted CX-029/CX-030 artifacts.
    subprocess.run([
        'python3', str(REPO / 'tools/map_campaign_art.py'), '--index',
        str(asset_root / 'visual-index.json'), '--output', str(asset_root / 'cx031-mapping.json'),
        '--merge', str(asset_root / 'cx029-mapping.json')], check=True)
    mapping = json.loads((asset_root / 'cx031-mapping.json').read_text())
    partial = dict(mapping, ui=[], shadows={'content': [], 'instances': []})
    partial_path = output / 'partial-mapping.json'
    partial_path.write_text(json.dumps(partial, indent=2) + '\n')
    records = []

    def run(project, phase, mode):
        directory = output / f'{phase}-{mode}'
        directory.mkdir(exist_ok=True)
        env = dict(os.environ)
        env['EGO_ASSET_INDEX'] = str(asset_root / (
            'absent-index.json' if mode == 'fallback' else 'visual-index.json'))
        env['EGO_ASSET_MAPPING'] = str(partial_path if mode == 'partial'
                                       else asset_root / 'cx031-mapping.json')
        command = [args.godot, '--path', str(project), '--audio-driver', 'Dummy']
        if args.rehearse:
            command += ['--headless']
        else:
            command += ['--display-driver', 'x11']
        command += ['--script', str(REPO / 'tools/capture_reference.gd'), '--',
                    str(directory), phase]
        if args.rehearse:
            command += ['--rehearse']
        result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=120)
        log = result.stdout + result.stderr
        (directory / ('godot-rehearsal.log' if args.rehearse else 'godot-rendered.log')).write_text(log)
        screens = ['menu', 'map', 'home', 'battle']
        if phase == 'after':
            screens += ['action-picker', 'targeting']
        expected = [f'{phase}-{screen}-{w}x{h}.png' for screen in screens
                    for w, h in [(960, 540), (1152, 648), (1440, 810)]]
        passed = (result.returncode == 0 and 'ERROR:' not in log
                  and 'REFERENCE_REVIEW_COMPLETE' in log
                  and (args.rehearse or (log.count('CAPTURE ') == len(expected)
                       and log.count('error=0') == len(expected)
                       and all((directory / name).is_file() for name in expected))))
        records.append(dict(phase=phase, mode=mode, passed=passed,
                            rendered=not args.rehearse and passed, expected=expected,
                            directory=str(directory)))
        print(f'{phase}-{mode}: {"PASS" if passed else "BLOCKED/FAIL"}', flush=True)

    with tempfile.TemporaryDirectory(prefix='cx031-base-', dir=asset_root) as temporary:
        baseline = Path(temporary)
        archive = subprocess.run(['git', 'archive', BASE], cwd=REPO,
                                 check=True, capture_output=True).stdout
        with tarfile.open(fileobj=io.BytesIO(archive)) as stream:
            stream.extractall(baseline, filter='data')
        scan = subprocess.run([args.godot, '--headless', '--path', str(baseline),
                               '--editor', '--quit'], capture_output=True, text=True, timeout=120)
        (output / 'baseline-import.log').write_text(scan.stdout + scan.stderr)
        run(baseline, 'before', 'local')
    for mode in ['local', 'fallback', 'partial']:
        run(REPO, 'after', mode)
    name = 'rehearsal-results.json' if args.rehearse else 'capture-results.json'
    (output / name).write_text(json.dumps(records, indent=2) + '\n')
    return 0 if all(record['passed'] for record in records) else 1


if __name__ == '__main__':
    raise SystemExit(main())
