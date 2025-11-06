#!/usr/bin/env bash
set -euo pipefail

# Корень с кодом AndroidLibXrayLite (по умолчанию каталог, который клонируем в workflow)
CORE_DIR="${1:-${GITHUB_WORKSPACE:-.}/AndroidLibXrayLite}"

echo "[xudp] core dir: ${CORE_DIR}"

if [[ ! -d "$CORE_DIR" ]]; then
  echo "::warning::Core dir not found: ${CORE_DIR}. Skip XUDP patch."
  exit 0
fi

# Ищем go-файлы, где упоминается xray.xudp.basekey или XUDP-вещи
mapfile -t CANDIDATES < <(grep -RIl --include='*.go' -e 'xray\.xudp\.basekey' -e 'xray\.xudp' "${CORE_DIR}" || true)

if [[ "${#CANDIDATES[@]}" -eq 0 ]]; then
  echo "::warning::No xudp usages found. Nothing to patch."
  exit 0
fi

echo "[xudp] files to patch:"
printf ' - %s\n' "${CANDIDATES[@]}"

# Функция «мягкого» выпиливания XUDP:
#  - любое чтение xray.xudp превращаем в константный "off"
#  - любое чтение basekey — в пустую строку
#  - любые panics по basekey заменяем на лог + return/continue безопасно
patch_file () {
  local f="$1"
  # резервная копия
  cp -f "$f" "$f.bak"

  # 1) любые попытки включить XUDP — в off
  sed -i \
    -e 's/os\.Getenv\s*(\s*"xray\.xudp"\s*)/"off"/g' \
    -e 's/Getenv\s*(\s*"xray\.xudp"\s*)/"off"/g' \
    "$f"

  # 2) любое получение basekey — в пустую строку
  sed -i \
    -e 's/os\.Getenv\s*(\s*"xray\.xudp\.basekey"\s*)/""/g' \
    -e 's/Getenv\s*(\s*"xray\.xudp\.basekey"\s*)/""/g' \
    "$f"

  # 3) panics по basekey — в лог и безопасный выход из участка
  #   заменяем строки с "panic:.*xray.xudp.basekey.*" на:  log.Print("XUDP disabled"); return
  #   (return подходит для функций; если это не функция — компилятор подскажет. Но в большинстве случаев это происходит внутри функций и ок.)
  sed -i \
    -e 's/panic\s*(.*xray\.xudp\.basekey.*)/log.Print("XUDP disabled (panic removed)"); return/g' \
    "$f"

  # 4) иногда проверка делается через if len(key)!=32 { panic(...) } — упростим до no-op
  #    Меняем шаблон "len(.*) != 32" → "false" (условие никогда не сработает)
  sed -i \
    -e 's/len\s*(\s*[^)]\+)\s*!=\s*32/false/g' \
    "$f"
}

# Патчим все найденные кандидаты
for f in "${CANDIDATES[@]}"; do
  echo "[xudp] patching: $f"
  patch_file "$f"
done

# Если проект под git — проиндексируем изменения (не обязательно, но удобно для логов/диагностики)
if git -C "${CORE_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "${CORE_DIR}" status --porcelain
  git -C "${CORE_DIR}" add -A || true
fi

echo "[xudp] patch done"
