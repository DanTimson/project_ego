#!/usr/bin/env python3
"""Record CX-030 rendered interactions and game audio on normal WSL."""
import argparse
import json
import os
import re
from pathlib import Path
import shutil
import tempfile
import subprocess

REPO = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--asset-root', type=Path, required=True)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', 'godot'))
    parser.add_argument('--mode', choices=('local', 'fallback', 'partial'),
                        help='record a single asset mode')
    parser.add_argument('--size', choices=('960x540', '1152x648', '1440x810'),
                        help='record a single viewport size')
    args = parser.parse_args()
    root = args.asset_root.resolve(strict=True)
    output = root / 'captures' / 'cx030'
    output.mkdir(parents=True, exist_ok=True)
    missing = [name for name in ('ffmpeg', 'ffprobe') if not shutil.which(name)]
    if missing:
        parser.error('Host capture requires installed: ' + ', '.join(missing))
    # Preserve the private image boundary: mappings and recordings stay local.
    mapping = json.loads((root / 'cx029-mapping.json').read_text())
    partial = dict(mapping)
    partial['ui'] = []
    partial['units'] = {'content': [], 'instances': []}
    partial_path = output / 'partial-mapping.json'
    partial_path.write_text(json.dumps(partial, indent=2) + '\n')
    results = []
    modes = (args.mode,) if args.mode else ('local', 'fallback', 'partial')
    sizes = (args.size,) if args.size else ('960x540', '1152x648', '1440x810')
    for mode in modes:
        for size in sizes:
            width, height = map(int, size.split('x'))
            run_dir = output / f'{mode}-{width}x{height}'
            run_dir.mkdir(exist_ok=True)
            env = dict(os.environ)
            env['EGO_ASSET_INDEX'] = str(root / (
                'absent-index.json' if mode == 'fallback' else 'visual-index.json'))
            env['EGO_ASSET_MAPPING'] = str(partial_path if mode == 'partial'
                                           else root / 'cx029-mapping.json')
            video = run_dir / 'interaction.mkv'
            video.unlink(missing_ok=True)
            with tempfile.TemporaryDirectory(dir=run_dir) as scratch:
                movie = Path(scratch) / 'interaction.avi'
                result = subprocess.run([
                    args.godot, '--path', str(REPO), '--display-driver', 'x11',
                    '--resolution', f'{width}x{height}', '--borderless',
                    '--write-movie', str(movie),
                    '--fixed-fps', '30', '--disable-vsync', '--script',
                    'res://tools/capture_interaction.gd', '--', str(run_dir)],
                    env=env, capture_output=True, text=True, timeout=180)
                encoded = subprocess.run([
                    'ffmpeg', '-y', '-i', str(movie), '-map', '0:v:0',
                    '-map', '0:a:0', '-c:v', 'libx264', '-preset', 'ultrafast',
                    '-crf', '20', '-c:a', 'pcm_s16le', str(video)],
                    capture_output=True, text=True)
                (run_dir / 'recorder.log').write_text(encoded.stderr)
            game_log = result.stdout + result.stderr
            (run_dir / 'godot.log').write_text(game_log)
            probe = subprocess.run(['ffprobe', '-v', 'error', '-show_streams', '-show_format',
                                    '-of', 'json', str(video)], capture_output=True, text=True)
            metadata = json.loads(probe.stdout or '{}')
            duration = float(metadata.get('format', {}).get('duration', 0))
            streams = metadata.get('streams', [])
            picture = subprocess.run([
                'ffmpeg', '-i', str(video), '-vf',
                'blackdetect=d=0:pix_th=0.04:pic_th=0.99', '-an', '-f', 'null', '-'],
                capture_output=True, text=True)
            (run_dir / 'video-review.log').write_text(picture.stderr)
            black_seconds = sum(map(float, re.findall(r'black_duration:([\d.]+)', picture.stderr)))
            has_picture = picture.returncode == 0 and duration > 0 and black_seconds < duration / 2
            correct_size = any(stream.get('width') == width and stream.get('height') == height
                               for stream in streams if stream['codec_type'] == 'video')
            audio = subprocess.run(['ffmpeg', '-i', str(video), '-af', 'astats',
                                    '-vn', '-f', 'null', '-'], capture_output=True, text=True)
            (run_dir / 'audio-review.log').write_text(audio.stderr)
            peaks = re.findall(r'Peak level dB:\s+(-?(?:\d+(?:\.\d+)?|inf))', audio.stderr)
            has_signal = any(float(peak) > -70 for peak in peaks)
            passed = (result.returncode == 0 and encoded.returncode == 0
                      and probe.returncode == 0 and has_picture and correct_size
                      and 'ERROR:' not in game_log
                      and 'INTERACTION_CAPTURE_COMPLETE' in game_log
                      and {s['codec_type'] for s in streams} >= {'audio', 'video'}
                      and audio.returncode == 0 and has_signal)
            results.append({'mode': mode, 'size': [width, height], 'passed': passed,
                            'video': str(video)})
            print(f'{mode} {width}x{height}: {"PASS" if passed else "FAIL"}', flush=True)
    (output / 'capture-results.json').write_text(json.dumps(results, indent=2) + '\n')
    return 0 if all(row['passed'] for row in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
