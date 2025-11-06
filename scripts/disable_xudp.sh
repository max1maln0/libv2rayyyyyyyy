#!/usr/bin/env bash
set -euo pipefail

# Папка с исходниками xray-core внутри твоего форка AndroidLibXrayLite.
# Подстрой, если у тебя другой путь.
CORE_DIR="AndroidLibXrayLite/xray-core"

echo "[xudp] disabling XUDP in ${CORE_DIR}"

# 1) Нейтрализуем вызов инициализации XUDP на Android:
#    часто он сидит в файле вроде transport/internet/xudp/xudp_android.go
#    и выглядит как: func init() { mustLoadBaseKey() }
#    Заменим тело init на no-op.
grep -Rsl --include='*xudp*_android*.go' 'func init()' "${CORE_DIR}" \
 | xargs -r sed -i 's/func init() {[^}]*}/func init() { \/* XUDP disabled on Android *\/ }/g'

# 2) Делаем mustLoadBaseKey() безопасной заглушкой (если встречается).
grep -Rsl --include='*xudp*.go' 'mustLoadBaseKey()' "${CORE_DIR}" \
 | xargs -r sed -i 's/func mustLoadBaseKey() {[^}]*}/func mustLoadBaseKey() { \/* no-op: XUDP disabled *\/ }/g'

# 3) Любые паники по basekey превращаем в лог и return.
grep -Rsl --include='*xudp*.go' 'xray.xudp.basekey' "${CORE_DIR}" \
 | xargs -r sed -i 's/panic(.*BaseKey.*)/log.Println("XUDP disabled on Android: skipping basekey check"); return/g'

# 4) Если есть флаг включённости XUDP — выключаем.
#    Например, переменные/функции Enabled()/enabled = true → false
grep -Rsl --include='*xudp*.go' -E '\bEnabled\(|enabled\s*:|enabled\s*=' "${CORE_DIR}" \
 | xargs -r sed -i 's/\benabled\b\s*=\s*true/enabled = false/g; s/\bEnabled()\s*{\s*return true/Enabled(){ return false/g'

echo "[xudp] patch applied."
