#!/usr/bin/env python3
"""Adds an agent's mark to the asset catalog as a vector template image.

Usage: scripts/add-agent-mark.py <AssetName> <mark.svg>

The source is a single-path, 24×24 SVG, such as one from LobeHub Icons. The asset is tinted in
code (`AgentKind.markTint`), so the fill colour in the source does not matter.

CoreSVG, which draws asset-catalog SVGs, misreads an arc whose flags are packed against the next
number (`a6 6 0 013.04-.41` is flags 0 and 1, then 3.04) and draws a line or a wrong arc in its
place, with only a log line to say so. Icon sets minify paths that way, so the path is rewritten
here with every number and flag separated.
"""
import json
import pathlib
import re
import sys

NUMBER = re.compile(r'[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?')
ARITY = dict(zip('MLHVCSQTAZ', [2, 2, 1, 1, 6, 4, 4, 2, 7, 0]))


def separated(d):
    out, i = [], 0
    while i < len(d):
        if d[i].isspace() or d[i] == ',':
            i += 1
            continue
        if not d[i].isalpha():
            sys.exit(f'expected a path command at {i}: {d[i:i + 20]!r}')
        command, i = d[i], i + 1
        params = []
        while True:
            while i < len(d) and (d[i].isspace() or d[i] == ','):
                i += 1
            if i >= len(d) or d[i].isalpha():
                break
            if command in 'Aa' and len(params) % 7 in (3, 4):
                params.append(d[i])  # an arc flag is exactly one character
                i += 1
            else:
                match = NUMBER.match(d, i)
                if not match:
                    sys.exit(f'expected a number at {i}: {d[i:i + 20]!r}')
                params.append(match.group())
                i = match.end()
        arity = ARITY[command.upper()]
        if (arity == 0 and params) or (arity and len(params) % arity):
            sys.exit(f'{command} takes {arity} numbers at a time, got {len(params)}')
        out.append(command + ' '.join(params))
    return ' '.join(out)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__.split('\n\n')[1])
    name, source = sys.argv[1], pathlib.Path(sys.argv[2])
    paths = re.findall(r'<path\b[^>]*\sd="([^"]+)"', source.read_text())
    if len(paths) != 1:
        sys.exit(f'{source} has {len(paths)} paths; a mark has one')

    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'
           f'<path fill="#000000" fill-rule="evenodd" clip-rule="evenodd" d="{separated(paths[0])}"/></svg>\n')
    folder = pathlib.Path(__file__).resolve().parent.parent / f'NotBoringNotch/Assets.xcassets/{name}.imageset'
    folder.mkdir(exist_ok=True)
    (folder / f'{name}.svg').write_text(svg)
    (folder / 'Contents.json').write_text(json.dumps({
        'images': [{'filename': f'{name}.svg', 'idiom': 'universal'}],
        'info': {'author': 'xcode', 'version': 1},
        'properties': {'preserves-vector-representation': True, 'template-rendering-intent': 'template'},
    }, indent=2) + '\n')
    print(f'wrote {folder}')


if __name__ == '__main__':
    main()
