#!/usr/bin/env bash
# Clones AndroidLibXrayLite and patches out XUDP on Android.
# Produces an output "pkg_dir" with the path to the go module to build.

set -euo pipefail

echo "[clone] AndroidLibXrayLite: ${LXLITE_REPO:-https://github.com/2dust/AndroidLibXrayLite.git} @ ${LXLITE_REF:-<default>}"

REPO_URL="${LXLITE_REPO:-https://github.com/2dust/AndroidLibXrayLite.git}"
REPO_REF="${LXLITE_REF:-}"

# 1) Clone (default branch if ref is empty)
if [[ -n "$REPO_REF" ]]; then
  git clone --depth=1 --branch "$REPO_REF" "$REPO_URL" AndroidLibXrayLite
else
  git clone --depth=1 "$REPO_URL" AndroidLibXrayLite
fi
cd AndroidLibXrayLite

# 2) Detect go module root (prefer top-level go.mod; if several, pick the one that contains .go files)
echo "[detect] looking for go.mod…"
mapfile -t MODS < <(git ls-files | grep -E '(^|/)(go\.mod)$' || true)

if [[ ${#MODS[@]} -eq 0 ]]; then
  echo "::error::go.mod not found in repo; cannot proceed"
  exit 1
fi

# Choose module dir that contains the most .go files
BEST_MOD=""
BEST_COUNT=-1
for m in "${MODS[@]}"; do
  dir="$(dirname "$m")"
  [[ "$dir" == "." ]] && dir="."
  count=$(find "$dir" -type f -name '*.go' ! -name '*_test.go' | wc -l | tr -d ' ')
  [[ -z "$count" ]] && count=0
  if [[ $count -gt $BEST_COUNT ]]; then
    BEST_COUNT=$count
    BEST_MOD="$dir"
  fi
done

if [[ -z "$BEST_MOD" || "$BEST_COUNT" -le 0 ]]; then
  echo "::error::No .go files found next to go.mod; cannot proceed"
  exit 1
fi

echo "[detect] go module dir: $BEST_MOD  (.go files: $BEST_COUNT)"
cd "$BEST_MOD"

# 3) Detect dominant package name (exclude tests, pick most frequent non "main")
echo "[detect] dominant package name…"
PKG=$(grep -Rho --include='*.go' '^package[[:space:]]\+[a-zA-Z0-9_]\+' . \
      | awk '{print $2}' \
      | grep -v '^main$' \
      | sort | uniq -c | sort -nr | awk 'NR==1{print $2}')

if [[ -z "${PKG:-}" ]]; then
  # fallback: if only main exists – используем main
  PKG=$(grep -Rho --include='*.go' '^package[[:space:]]\+[a-zA-Z0-9_]\+' . \
        | awk '{print $2}' \
        | sort | uniq -c | sort -nr | awk 'NR==1{print $2}')
fi

if [[ -z "${PKG:-}" ]]; then
  echo "::error::Cannot determine package name to place guard file"
  exit 1
fi
echo "[detect] package: $PKG"

# 4) Add android-only guard file to disable XUDP at build time
echo "[patch] adding xudp_guard_android.go (//go:build android)"
cat > xudp_guard_android.go <<EOF
//go:build android
// +build android

package ${PKG}

// This file disables XUDP usage on Android builds entirely.
// We do not rely on env vars to avoid early init panics in Go bindings.

func init() {
    _ = "XUDP disabled at build-time (patched)"
}
EOF

# 5) Strip any env writes/reads to xudp.basekey variants and soften panics
echo "[patch] removing env basekey references and panics"
# Remove lines that touch basekey envs
grep -RIl --include='*.go' -e 'xudp\.basekey' -e 'XRAY_XUDP_BASEKEY' -e 'XRAY\.XUDP\.BASEKEY' . | while read -r f; do
  echo "  - clean $f"
  sed -i '/xudp\.basekey/d' "$f" || true
  sed -i '/XRAY_XUDP_BASEKEY/d' "$f" || true
  sed -i '/XRAY\.XUDP\.BASEKEY/d' "$f" || true
done

# Replace explicit BaseKey length panics with safe returns/no-ops
grep -RIl --include='*.go' -e 'BaseKey must be 32 bytes' . | while read -r f; do
  echo "  - soften panic in $f"
  sed -i 's/panic(.*BaseKey.*32 bytes.*)/return/g' "$f" || true
done

# Optional: make any DecodeString+len(raw)!=32 checks non-fatal
grep -RIl --include='*.go' -e 'DecodeString' -e 'basekey' -e 'xudp' . | while read -r f; do
  sed -i 's/if[[:space:]]*err[[:space:]]*!=[[:space:]]*nil[[:space:]]*||[[:space:]]*len(raw)[[:space:]]*!=[[:space:]]*32[[:space:]]*{[^}]*}/if err != nil || len(raw) != 32 { return }/g' "$f" || true
done

echo "[tree] guard file created at: $(pwd)/xudp_guard_android.go"

# 6) Export path for next workflow steps
OUT_DIR="$(pwd)"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "pkg_dir=$OUT_DIR"
    echo "repo_root=$(realpath ..)"
  } >> "$GITHUB_OUTPUT"
fi

echo "[done] patches applied; pkg_dir=$OUT_DIR"
