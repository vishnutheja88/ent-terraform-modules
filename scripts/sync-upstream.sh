#!/usr/bin/env bash
# Vendor / upgrade terraform-aws-modules into upstream/ at pinned tags,
# then rewrite nested public-Registry module calls to local vendored paths.
#
# Usage:
#   scripts/sync-upstream.sh                 # re-vendor everything at the pins below
#   scripts/sync-upstream.sh eks v21.31.0    # bump one module
#
# Enterprise: point UPSTREAM_BASE at your Bitbucket mirror, e.g.
#   UPSTREAM_BASE=https://bitbucket.company.com/scm/mirror scripts/sync-upstream.sh
set -euo pipefail

UPSTREAM_BASE="${UPSTREAM_BASE:-https://github.com/terraform-aws-modules}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/upstream"

declare -A PINS=(
  [vpc]=v6.8.0
  [ec2-instance]=v6.4.1
  [iam]=v6.11.1
  [route53]=v6.5.1
  [eks]=v21.30.2
  [kms]=v4.2.2
  [security-group]=v6.0.0
  [s3-bucket]=v5.18.0
)

if [[ $# -eq 2 ]]; then
  [[ -n "${PINS[$1]:-}" ]] || { echo "unknown module: $1"; exit 1; }
  PINS[$1]="$2"
  ONLY="$1"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for name in "${!PINS[@]}"; do
  [[ -n "${ONLY:-}" && "$name" != "$ONLY" ]] && continue
  tag="${PINS[$name]}"
  repo="terraform-aws-$name"
  echo "==> $repo @ $tag"
  git clone -q --depth 1 --branch "$tag" "$UPSTREAM_BASE/$repo.git" "$tmp/$repo"
  rm -rf "$tmp/$repo"/{.git,examples,tests,wrappers,.github,docs,mkdocs.yml,.pre-commit-config.yaml,.releaserc.json,.editorconfig,.gitignore,Makefile}
  rm -rf "${DEST:?}/$repo"
  mv "$tmp/$repo" "$DEST/$repo"
done

echo "==> Rewriting nested Registry module calls to vendored paths"
# terraform-aws-modules/<name>/aws  ->  ../terraform-aws-<name>   (and drop the version pin line)
grep -rlE '^\s*source\s*=\s*"terraform-aws-modules/[a-z0-9-]+/aws"' "$DEST" --include='*.tf' | while read -r f; do
  python3 - "$f" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
out, skip_version = [], False
for line in s.splitlines(keepends=True):
    m = re.match(r'^(\s*)source\s*=\s*"terraform-aws-modules/([a-z0-9-]+)/aws"', line)
    if m:
        out.append(f'{m.group(1)}source = "../terraform-aws-{m.group(2)}" # vendored by sync-upstream.sh\n')
        skip_version = True
        continue
    if skip_version and re.match(r'^\s*version\s*=', line):
        skip_version = False
        continue
    skip_version = False
    out.append(line)
open(p, "w").write("".join(out))
print("  patched", p)
PY
done

echo "==> Remaining external module references (should be none outside READMEs):"
grep -rnE '^\s*source\s*=\s*"[^.]' "$DEST" --include='*.tf' | grep -v '"hashicorp/' || echo "  none"

echo "Done. Update upstream/VERSIONS.md, then run: terraform -chdir=blueprint init -backend=false && terraform -chdir=blueprint validate"
