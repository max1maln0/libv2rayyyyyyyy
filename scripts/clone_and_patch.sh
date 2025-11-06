#!/usr/bin/env bash
set -euo pipefail

echo "[clone] AndroidLibXrayLite: $LXLITE_REPO @ $LXLITE_REF"
git clone --depth=1 --branch "$LXLITE_REF" "$LXLITE_REPO" AndroidLibXrayLite

cd AndroidLibXrayLite

# -------------------------------
# 1) Найдём go-модуль мобильной обвязки
# Обычно это AndroidLibXrayLite/mobile (в нём должен быть go.mod или исходники для gomobile).
# Если у тебя другая структура — поправь MOBILE_DIR ниже.
# -------------------------------
MOBILE_DIR="mobile"
if [ ! -d "$MOBILE_DIR" ]; then
  echo "::error::Не найден каталог '$MOBILE_DIR' в AndroidLibXrayLite. Поправь scripts/clone_and_patch.sh"
  exit 1
fi

# Ограничимся мобильным модулем
cd "$MOBILE_DIR"

echo "[info] go env:"
go env

# -------------------------------
# 2) Отключаем XUDP на Android: добавляем guard-файл
# -------------------------------
PKG_NAME="mobile"  # по умолчанию пакет часто называется 'mobile', поправь при необходимости

echo "[patch] добавляю xudp_guard_android.go (android build tag)…"
mkdir -p _patch
cp ../../patches/xudp_guard_android.go.tmpl _patch/xudp_guard_android.go
# Вставим правильное имя пакета
sed -i "s|__PKG__|${PKG_NAME}|g" _patch/xudp_guard_android.go
mv _patch/xudp_guard_android.go ./xudp_guard_android.go
rm -rf _patch

echo "[patch] xudp_guard_android.go:"
sed -n '1,120p' xudp_guard_android.go || true

# -------------------------------
# 3) Убираем любые установки basekey из Android-инициализации (env_android.go и т.п.)
# и заменяем panic в парсере basekey на «тихий» возврат.
#
# Патч сделан «широким»:
# - вычищает строки с XRAY_XUDP_BASEKEY / xray.xudp.basekey / XRAY.XUDP.BASEKEY
# - заменяет panic(...BaseKey must be 32 bytes...) на return
# - если есть функция типа xudpMaybeInit() — она остаётся, но на Android не вызовется (guard)
# -------------------------------

echo "[patch] вычищаю setenv basekey в *.go…"
grep -RIl --include='*.go' -e 'xudp.basekey' -e 'XRAY_XUDP_BASEKEY' -e 'XRAY.XUDP.BASEKEY' . | while read -r f; do
  echo "  - patch $f"
  sed -i '/xudp\.basekey/d' "$f" || true
  sed -i '/XRAY_XUDP_BASEKEY/d' "$f" || true
  sed -i '/XRAY\.XUDP\.BASEKEY/d' "$f" || true
done

echo "[patch] делаю парсинг basekey «мягким» (без panic)…"
grep -RIl --include='*.go' -e 'BaseKey must be 32 bytes' . | while read -r f; do
  echo "  - patch $f"
  # Заменим panic(...) на return
  sed -i 's/panic(.*BaseKey must be 32 bytes.*)/return/g' "$f" || true
done

# В некоторых репо panic-сообщение может быть иначе сформулировано — добавим запасные «тихие» замены:
grep -RIl --include='*.go' -e 'xudp' -e 'basekey' . | while read -r f; do
  # Если есть DecodeString и проверка длины == 32 — поставим «тихий» путь
  sed -i 's/if err != nil \|\| len(raw) != 32 {[^}]*}/if err != nil || len(raw) != 32 { return }/g' "$f" || true
done

echo "[patch] итоговое дерево:"
find . -maxdepth 2 -type f -name '*.go' -print

echo "[done] патчи применены."
