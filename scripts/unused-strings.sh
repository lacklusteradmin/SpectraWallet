#!/usr/bin/env bash
# Shipped copy nothing reads.
#
# Everything under `resources/` ships whether or not it is read. The
# `RuntimeStrings` tables are the only localized copy, and most keys are the
# English string itself, so a line deleted from a view leaves its
# translations behind. 543 of 1389 once had no source left anywhere.
#
# A key is reachable when its text, with `%@`/`%lld`/… treated as a wildcard,
# appears anywhere that can produce it: Swift, Rust (core writes English
# templates too — see `diagnostics/degraded.rs`), another resource file, or
# the chain catalog. A dotted key is reachable when it is spelled out — the
# screen copy structs name theirs — or when its namespace is interpolated
# with an id (`"addressHint.\(chain.id).empty"`). The reverse holds too: a
# dotted key Swift spells out must be in the source table.
#
# Locales are checked against each other as well: a key set that drifts means
# one language silently falls back to another.
#
# Exits non-zero when any are found, so it can gate.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json, pathlib, re, subprocess, sys

def hand_written(root, suffix):
    """Files under `root` a person wrote: tracked or new, never ignored.

    Walking the directory reads the bindings too — `swift/generated/` and the
    Kotlin `uniffi/` package, both ignored and both present once bindgen has
    run. Generated code calls every export and quotes every doc comment, so
    it made each check pass on a machine that had built for that platform.
    """
    listed = subprocess.run(
        ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', root],
        check=True, capture_output=True, text=True).stdout.split('\0')
    return [pathlib.Path(p) for p in sorted(listed) if p.endswith(suffix) and pathlib.Path(p).exists()]

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
    paths = [p for suffix, roots in (
                 ('.swift', ('swift',)), ('.rs', ('core', 'cli', 'ffi')),
                 ('.json', ('resources',)), ('.toml', ('core/data',)),
                 ('.kt', ('kotlin',)), ('.xml', ('kotlin',)))
             for root in roots for p in hand_written(root, suffix)
             if not p.name.startswith('RuntimeStrings.')]
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

def dotted_reachable(key):
    namespace = re.split(r'[._]', key, maxsplit=1)[0]
    return key in haystack or f'{namespace}.\\(' in haystack or f'{namespace}_\\(' in haystack

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
        found = (dotted_reachable(key) if DOTTED.match(key) and ' ' not in key
                 else reachable(key, haystack))
        if not found:
            failures.append(f"  {base:<36} no source produces {key!r}")

# The reverse: a dotted key spelled out in Swift must be in the source table,
# or the screen shows the key itself.
source_keys = set(json.loads((STRINGS / 'RuntimeStrings.en.json').read_text()))
swift = '\n'.join(p.read_text() for p in hand_written('swift', '.swift'))
for key in sorted(set(re.findall(r'AppLocalization\.(?:string|format)\("([A-Za-z_]+\.[A-Za-z0-9_.-]+)"', swift))):
    if key not in source_keys:
        failures.append(f"  {'RuntimeStrings.en.json':<36} Swift names a missing key {key!r}")

for line in failures:
    print(line)
print(f"\n  {len(failures)} unused or inconsistent string(s)")
sys.exit(1 if failures else 0)
PY
