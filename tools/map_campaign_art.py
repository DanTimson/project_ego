#!/usr/bin/env python3
"""Write the inspected Genesis presentation selection beside a private index.

No images are copied. Existing version-1/2 selections can be merged explicitly.
The result remains a version-2 mapping accepted by the exact-closure packager.
"""
import argparse
import json
from pathlib import Path

from build_demo import mapping_references, load_source_index, prepare_minimal_asset_bundle

UI = {
    'crystal': 'Interface:77Crystal',
    'cancel_normal': 'Buttons:84CancelN', 'cancel_hover': 'Buttons:85CancelA',
    'cancel_pressed': 'Buttons:86CancelP', 'spell_disabled': 'Buttons:24ButtSpellI',
    'menu_panorama': 'Interface:85Eador', 'menu_frame': 'Interface:84MainMenu',
    'menu_normal': 'Interface:86MenuStrN', 'menu_hover': 'Interface:87MenuStrA',
    'home_background': 'Castle:000Background', 'home_estate': 'Castle:001Estate',
    'home_recovery': 'Castle:016RecruitPointe', 'home_recruit': 'Castle:017Barracks',
    'dialog': 'Interface:52Dialog01', 'gold': 'Interface:76Gold',
    'map_grass': 'Nature:000Grass', 'map_tree': 'Nature:005Trees',
    'map_mountain': 'Nature:011Mount',
    'map_home': 'Castle:001Estate', 'map_ford': 'Site:012Farm',
    'map_quarry': 'Site:014Silver', 'map_watchpost': 'Site:011Tower',
    'map_mill': 'Site:013Windmill', 'map_keep': 'Castle:019Watchtower',
    'owner_hostile': 'MapObj:24Herb01', 'owner_friendly': 'MapObj:25Herb02',
    'position_ring': 'MapObj:40Selection', 'route_marker': 'MapObj:41PathG',
    'panel': 'Battlefield:02Panel', 'unit_bar': 'Battlefield:13UnitBar',
    'target': 'Battlefield:14Target', 'selection': 'Battlefield:16Selection',
    'life': 'Ability:001Life', 'attack': 'Ability:002Attack',
    'defence': 'Ability:004Defence', 'ranged': 'Ability:008RangedAttack',
    'ammo': 'Ability:010Ammo', 'stamina': 'Ability:011Stamina',
    'morale': 'Ability:012Morale',
    'pass_normal': 'Buttons:08ButtEndN', 'pass_hover': 'Buttons:09ButtEndA',
    'pass_pressed': 'Buttons:10ButtEndP', 'pass_disabled': 'Buttons:11ButtEndI',
}
# Stable canonical content and explicitly assigned presentation roles only.
CONTENT = {'campaign:unit/1': '03', 'campaign:unit/2': '04', 'campaign:unit/3': '05'}
INSTANCES = {'azure-vanguard-01': '03', 'azure-ranger-17': '04',
             'crimson-guard-42': '05', 'crimson-marksman-88': '07'}


def selection():
    result = {'version': 2}
    for category, archive in [('units', 'Units'), ('shadows', 'Unit_shadow'),
                              ('portraits', 'Unit_icons')]:
        result[category] = {
            'content': [{'id': k, 'asset': f'{archive}:Unit{v}'} for k, v in CONTENT.items()],
            'instances': [{'id': k, 'asset': f'{archive}:Unit{v}'} for k, v in INSTANCES.items()],
        }
        ui_role = {'id': f'campaign_guard_{category}', 'asset': f'{archive}:Unit05'}
        result.setdefault('ui', []).append(ui_role)
    result['ui'] += [{'id': k, 'asset': v} for k, v in UI.items()]
    result['terrain'] = [{'id': 'base', 'asset': 'Battlefield:03Grass01'}] + [
        {'id': f'variation_{i}', 'asset': f'Battlefield:0{i+3}Grass0{i+1}'} for i in range(3)]
    result['decorations'] = [{'id': f'grass_{i}', 'asset': f'Nature:{i+21:03}GrassObj'}
                             for i in range(4)]
    return result


def merge(previous, current):
    """Preserve unrelated mappings; this inspected selection owns its named slots."""
    if previous['version'] == 1:
        previous = {'version': 2, 'units': {k: previous[k] for k in ('content', 'instances')},
                    'shadows': {'content': [], 'instances': []},
                    'portraits': {'content': [], 'instances': []},
                    'terrain': [], 'decorations': [], 'ui': []}
    mapping_references(previous)
    for category in ('units', 'shadows', 'portraits', 'terrain', 'decorations', 'ui'):
        groups = ('content', 'instances') if isinstance(current[category], dict) else (None,)
        for group in groups:
            old = previous[category][group] if group else previous[category]
            new = current[category][group] if group else current[category]
            values = {item['id']: item for item in old}
            values.update({item['id']: item for item in new})
            merged = [values[key] for key in sorted(values)]
            if group:
                current[category][group] = merged
            else:
                current[category] = merged
    return current


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--index', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--merge', type=Path)
    parser.add_argument('--bundle', type=Path, help='new exact-closure directory beside the index')
    args = parser.parse_args()
    if args.output.resolve().parent != args.index.resolve().parent:
        parser.error('write the mapping beside the private index')
    result = selection()
    if args.merge:
        result = merge(json.loads(args.merge.read_text()), result)
    assets = load_source_index(args.index.parent, args.index.name)
    missing = mapping_references(result) - assets.keys()
    if missing:
        parser.error(f'index lacks inspected images: {sorted(missing)}')
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(f'Wrote {len(mapping_references(result))} image references to {args.output}')
    if args.bundle:
        if args.bundle.resolve().parent != args.index.resolve().parent:
            parser.error('bundle must be a new directory beside the private index')
        prepare_minimal_asset_bundle(args.index.parent, args.bundle,
                                     index_name=args.index.name, mapping_name=args.output.name)
        print(f'Validated exact private closure: {args.bundle}')


if __name__ == '__main__':
    main()
