#!/usr/bin/env bash
# Exports no front end can reach.
#
# An FFI export nothing calls still costs: it is generated into the bindings,
# it has to keep compiling, and it reads as API. This lists the ones whose
# camelCase name appears nowhere in hand-written Swift or in the CLI.
#
# Exits non-zero when any are found, so it can gate.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import re, pathlib, sys

def camel(s):
    head, *rest = s.split('_')
    return head + ''.join(p[:1].upper() + p[1:] for p in rest)

names = []
for f in sorted(pathlib.Path('core/src').rglob('*.rs')):
    t = f.read_text()
    for m in re.finditer(r'#\[uniffi::export[^\]]*\]\s*\npub(?:\([^)]*\))? (?:async )?fn (\w+)', t):
        names.append((m.group(1), str(f.relative_to('core/src'))))
    for m in re.finditer(r'#\[uniffi::export[^\]]*\]\s*\nimpl ([^\{]*)\{', t):
        i, depth = m.end(), 1
        while depth and i < len(t):
            depth += (t[i] == '{') - (t[i] == '}')
            i += 1
        for n in re.findall(r'\n    pub(?:\([^)]*\))? (?:async )?fn (\w+)', t[m.end():i]):
            names.append((n, str(f.relative_to('core/src'))))

def calls_only(source, language):
    # Declarations and comments are not evidence of calls. In particular a Swift
    # helper may have the same camelCase name as an unused Rust export.
    source = re.sub(r'/\*.*?\*/', '', source, flags=re.S)
    source = re.sub(r'(?m)^\s*//.*$', '', source)
    keyword = 'func' if language == 'swift' else 'fn'
    return re.sub(r'\b' + keyword + r'\s+\w+', keyword + ' __declaration__', source)

swift = calls_only('\n'.join(f.read_text() for f in pathlib.Path('swift').rglob('*.swift')
                if 'generated' not in f.parts), 'swift')
cli = calls_only('\n'.join(f.read_text() for f in pathlib.Path('cli/src').rglob('*.rs')), 'rust')

# Known-reachable by another route: the CLI drives these by their Rust name,
# and `new` is a constructor UniFFI needs.
ALLOWED = {'new'}

dead = [(n, f) for n, f in names
        if n not in ALLOWED
        and not re.search(rf'\b{re.escape(camel(n))}\s*\(', swift)
        and not re.search(rf'\b{re.escape(n)}\s*\(', cli)]

for n, f in sorted(dead):
    print(f"  {n:<46} {f}")
print(f"\n  {len(dead)} unreachable export(s)")
sys.exit(1 if dead else 0)
PY
