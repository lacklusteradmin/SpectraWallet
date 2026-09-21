#!/usr/bin/env bash
# Shipped copy nothing reads.
#
# Everything under `resources/` ships whether or not it is read, and two
# shapes of copy rot differently:
#
#   * A `*Content.<locale>.json` key with no field on its `Decodable` struct
#     is dropped on the floor by `JSONDecoder` — silently, because decoding
#     ignores unknown keys. Seven of `DiagnosticsContent`'s twenty-nine were.
#   * A `RuntimeStrings` key is looked up by the English string itself, so a
#     line deleted from a view leaves its translations behind. 543 of 1389
#     had no source left anywhere.
#
# A runtime key is reachable when its text, with `%@`/`%lld`/… treated as a
# wildcard, appears anywhere that can produce it: Swift, Rust (core writes
# English templates too — see `diagnostics/degraded.rs`), another resource
# file, or the chain catalog. Dotted keys are built at runtime from an id
# (`addressHint.bitcoin.empty`), so a namespace prefix is enough.
#
# Locales are checked against each other as well: a key set that drifts means
# one language silently falls back to another.
#
# Exits non-zero when any are found, so it can gate.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json, pathlib, re, sys

STRINGS = pathlib.Path('resources/strings')
FORMAT = re.compile(r'%(?:@|%|lld|llu|ld|lu|d|u|f|s|\d*\.\d+f|\.\d+f)')
# Catalog IDs can contain hyphens, e.g. endpointCapability.token-history.
DOTTED = re.compile(r'^[a-zA-Z_]+[._][a-zA-Z0-9_.-]+$')

def corpus():
    """Every file that could name a string, with continuations flattened.

    A Rust or Swift literal may be split across lines with a trailing `\\`,
    and the whitespace that follows is indentation rather than part of the
    string. Squeezing both means a wrapped literal still matches the one-line
    key it produces.
    """
    paths = [p for pattern, roots in (
                 ('*.swift', ('swift',)), ('*.rs', ('core', 'cli', 'ffi')),
                 ('*.json', ('resources',)), ('*.toml', ('core/data',)),
                 ('*.kt', ('kotlin',)), ('*.xml', ('kotlin',)))
             for root in roots for p in pathlib.Path(root).rglob(pattern)
             if 'target' not in p.parts and not p.name.startswith('RuntimeStrings.')]
    text = '\n'.join(p.read_text(errors='replace') for p in paths)
    return re.sub(r'\s+', ' ', re.sub(r'\\\s*\n\s*', '', text))

def reachable(key, haystack):
    """A key is reachable when its literal text, wildcarded at each format
    specifier, is somewhere that could produce it."""
    pieces = [re.escape(p) for p in FORMAT.split(re.sub(r'\s+', ' ', key).strip()) if p]
    return bool(pieces) and re.search('.{0,120}'.join(pieces), haystack)

def locales(base):
    # `RuntimeStrings.manifest.json` sits beside the locales and names them;
    # it is not one of them.
    return sorted(p for p in STRINGS.glob(f'{base}.*.json')
                  if not p.name.endswith('.manifest.json'))

failures = []
haystack = corpus()
swift = '\n'.join(p.read_text() for p in pathlib.Path('swift').rglob('*.swift')
                  if 'generated' not in p.parts)
swift_identifiers = set(re.findall(r'[A-Za-z_][A-Za-z_0-9]*', swift))

bases = sorted({p.name.split('.')[0] for p in STRINGS.glob('*.*.json')
                if not p.name.endswith('.manifest.json')})
for base in bases:
    files = locales(base)
    if not files:
        continue
    keysets = {p.name: set(json.loads(p.read_text())) for p in files
               if isinstance(json.loads(p.read_text()), dict)}
    if not keysets:
        continue
    reference = set().union(*keysets.values())
    for name, keys in keysets.items():
        for missing in sorted(reference - keys):
            failures.append(f"  {name:<36} missing key present in another locale: {missing!r}")

    source = json.loads(files[0].read_text())
    for key in sorted(source):
        if base == 'RuntimeStrings':
            if DOTTED.match(key) and ' ' not in key:
                continue
            if not reachable(key, haystack):
                failures.append(f"  {base:<36} no source produces {key!r}")
        elif key not in swift_identifiers:
            failures.append(f"  {base:<36} no struct field decodes {key!r}")

for line in failures:
    print(line)
print(f"\n  {len(failures)} unused or inconsistent string(s)")
sys.exit(1 if failures else 0)
PY
