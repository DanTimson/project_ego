"""Presentation selection stays in the existing closure and mapping contracts."""
import json
from pathlib import Path
import subprocess
import sys

import pytest

from build_demo import BuildError, mapping_references, prepare_minimal_asset_bundle
from map_campaign_art import merge, selection


def test_selection_and_legacy_merge():
    mapping = selection()
    refs = mapping_references(mapping)
    legacy = {'version': 1, 'content': [], 'instances': [
        {'id': 'external-figure', 'asset': 'Synthetic:Figure'}]}
    merged = merge(legacy, mapping)
    assert mapping_references(merged) == refs | {'Synthetic:Figure'}
    assert merged['units']['instances'][0]['id'] != ''
    assert legacy['instances'][0] in merged['units']['instances']


def test_named_source_closure_and_cli(tmp_path):
    # Synthetic bytes, no original images. Exercise all new slots through the
    # existing packager's strict reference closure and duplicate/escape guards.
    mapping = selection()
    assets = []
    for i, key in enumerate(sorted(mapping_references(mapping))):
        archive, source_id = key.split(':')
        name = f'{i}.bmp'
        (tmp_path / name).write_bytes(b'synthetic image bytes')
        assets.append(dict(key=key, archive=archive, source_id=source_id,
                           path=name, type='image'))
    (tmp_path / 'unused.bmp').write_bytes(b'unmapped original stand-in')
    assets.append(dict(key='Unused:Figure', archive='Unused', source_id='Figure',
                       path='unused.bmp', type='image'))
    (tmp_path / 'visual-index.json').write_text(json.dumps({'version': 1, 'assets': assets}))
    command = [sys.executable, str(Path(__file__).with_name('map_campaign_art.py')),
               '--index', str(tmp_path / 'visual-index.json'), '--output', str(tmp_path / 'cx029-mapping.json'),
               '--bundle', str(tmp_path / 'cli-runtime')]
    result = subprocess.run(command, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert len(list((tmp_path / 'cli-runtime' / 'assets').iterdir())) == len(mapping_references(mapping))
    bundle = tmp_path / 'runtime'
    prepare_minimal_asset_bundle(tmp_path, bundle, index_name='visual-index.json',
                                 mapping_name='cx029-mapping.json')
    assert len(list((bundle / 'assets').iterdir())) == len(mapping_references(mapping))
    assert json.loads((bundle / 'mapping.json').read_text()) == mapping
    assert {a['key'] for a in json.loads((bundle / 'index.json').read_text())['assets']} == mapping_references(mapping)
    for kwargs in ({'index_name': '../elsewhere.json'}, {'mapping_name': '/tmp/mapping.json'}):
        with pytest.raises(BuildError, match='filename'):
            prepare_minimal_asset_bundle(tmp_path, tmp_path / 'unsafe', **kwargs)
