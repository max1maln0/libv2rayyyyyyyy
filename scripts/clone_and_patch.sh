#!/usr/bin/env bash
# scripts/clone_and_patch.sh
# Clones AndroidLibXrayLite and patches out XUDP on Android.

set -e
set -u
set -o pipefail

echo "[clone] AndroidLibXrayLite: ${LXLITE_REPO:-unset} @ ${LXLITE_REF:-unset}"

if [[ -z "${LXLITE_REPO:-}" || -z "${LXLITE_REF:-}" ]]; then
  echo "::error::LXLITE_REPO or LXLITE_REF env is not set (workflow sets them)."
  exit 1
fi

git clone --depth=1 --branch "$LXLITE_REF" "$LXLITE_REPO" AndroidLibXrayLite

cd AndroidLibXrayLite

# Папка мобильного go-модуля (поменяй, если у апстрима иная структура)
MOBILE_DIR="mobile"
if [[ ! -d "$MOBILE_DIR" ]]; then
  echo "::error::Не найден каталог '$MOBILE_DIR' в AndroidLibXrayLite. Поправь MOBILE_DIR в scripts/clone_and_patch.sh"
  exit 1
fi

cd "$MOBILE_DIR"

echo "[info] go env:"
go env || true

# ---------- 1) Добавляем guard-файл, который блокирует XUDP на ANDROID ----------
PKG_NAME="mobile"   # если пакет у апстрима другой — поменяй
echo "[patch] adding xudp_guard_android.go (android build tag)…"

TMPDIR="$(mktemp -d)"
cp ../../patches/xudp_guard_android.go.tmpl "${TMPDIR}/xudp_guard_android.go"
# подставим имя пакета
sed -i "s|__PKG__|${PKG_NAME}|g" "${TMPDIR}/xudp_guard_android.go"
mv "${TMPDIR}/xudp_guard_android.go" ./xudp_guard_android.go
rm -rf "${TMPDIR}"

echo "[show] xudp_guard_android.go (head):"
sed -n '1,120p' xudp_guard_android.go || true

# ---------- 2) Вычищаем любые setenv basekey в исходниках ----------
echo "[patch] removing any basekey setenv occurrences in *.go…"
# ищем и чистим известные имена переменных окружения
mapfile -t HIT_FILES < <(grep -RIl --include='*.go' -e 'xudp.basekey' -e 'XRAY_XUDP_BASEKEY' -e 'XRAY.XUDP.BASEKEY' . || true)
for f in "${HIT_FILES[@]:-}"; do
  echo "  - patch $f"
  sed -i '/xudp\.basekey/d' "$f" || true
  sed -i '/XRAY_XUDP_BASEKEY/d' "$f" || true
  sed -i '/XRAY\.XUDP\.BASEKEY/d' "$f" || true
done

# ---------- 3) Делаем парсинг basekey «тихим» (без panic) ----------
echo "[patch] softening basekey parsing (no panic)…"
mapfile -t PANIC_FILES < <(grep -RIl --include='*.go' -e 'BaseKey must be 32 bytes' . || true)
for f in "${PANIC_FILES[@]:-}"; do
  echo "  - patch $f (panic -> return)"
  # максимально широкая замена panic(...) на return
  sed -i 's/panic(.*BaseKey.*32 bytes.*)/return/g' "$f" || true
done

# запасные правки: если встретится типовая конструкция DecodeString + проверка длины
mapfile -t MAYBE_FILES < <(grep -RIl --include='*.go' -e 'DecodeString' -e 'basekey' -e 'xudp' . || true)
for f in "${MAYBE_FILES[@]:-}"; do
  # где есть проверка err/len != 32 — заставим «тихо» выйти
  sed -i 's/if[[:space:]]\+err[[:space:]]*!=[[:space:]]*nil[[:space:]]*||[[:space:]]*len(raw)[[:space:]]*!=[[:space:]]*32[[:space:]]*{[^}]*}/if err != nil || len(raw) != 32 { return }/g' "$f" || true
done

echo "[tree] resulting Go files (top 2 levels):"
find . -maxdepth 2 -type f -name '*.go' -print | sort

echo "[done] patches applied."
