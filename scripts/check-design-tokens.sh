#!/usr/bin/env bash
# Fails when a Swift view restates a design value that SpectraLayout owns.
#
#   scripts/check-design-tokens.sh
#
# docs/iosUI.md defines the corner-radius scale and the two Liquid Glass tints;
# swift/views/SpectraLayout.swift spells them in Swift. A screen that writes the
# number instead of the token drifts silently — before this check the app had
# grown a 0.033 and a 0.044 tint, three radii for one chip, and four radii for
# one input helper, none of which any review would catch by eye.
#
# The scale itself is not policed here. Changing a step is a design decision:
# edit docs/iosUI.md and SpectraLayout.swift together.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VIEWS="$REPO_ROOT/swift/views"
TOKENS="$VIEWS/SpectraLayout.swift"

fail=0
report() {
  local title="$1" remedy="$2" hits="$3"
  [[ -z "$hits" ]] && return 0
  printf '\n%s\n' "$title" >&2
  printf '%s\n' "$hits" | sed 's|^'"$REPO_ROOT"'/|  |' >&2
  printf '  -> %s\n' "$remedy" >&2
  fail=1
}

# A numeric radius at a call site. Component property declarations
# (`var cornerRadius: CGFloat = 6`) are a component's own geometry and do not
# match this pattern.
report "Numeric corner radius outside SpectraLayout:" \
  "use SpectraLayout.Radius (hero/card/compact/input/chip/pill/control)" \
  "$(grep -rn 'cornerRadius: [0-9]' --include='*.swift' "$VIEWS" | grep -v "^$TOKENS:" || true)"

# A raw neutral glass tint. Accent-tinted glass (.orange/.red notices) carries
# its own colour and is deliberately not a token.
report "Raw white glass tint outside SpectraLayout:" \
  "use SpectraLayout.GlassTint.elevated / .content, or spectraElevatedFill / spectraCardFill" \
  "$(grep -rn 'tint(\.white\.opacity(' --include='*.swift' "$VIEWS" | grep -v "^$TOKENS:" || true)"

if (( fail )); then
  printf '\ndesign tokens: FAILED\n' >&2
  exit 1
fi
printf 'design tokens: ok\n'
