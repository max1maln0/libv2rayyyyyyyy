# libv2ray.aar (Android, XUDP disabled) – CI template

Этот репозиторий собирает **патченный libv2ray.aar** через GitHub Actions:
- **XUDP на Android полностью отключён** (guard по build tag)
- Любые паники из-за `xray.xudp.basekey` превращены в «тихий» возврат
- На выходе — `libv2ray.aar` (по умолчанию `arm64-v8a`)

## Как использовать

1. Создай пустой репозиторий и добавь сюда все файлы из этого шаблона.
2. По желанию поправь переменные в `.github/workflows/build-libv2ray-aar.yml`:
   - `LXLITE_REPO` – URL апстрима (по умолчанию 2dust/AndroidLibXrayLite)
   - `LXLITE_REF`  – ветка/тег (по умолчанию `master`)
3. Запусти workflow: **Actions → Build libv2ray.aar → Run workflow**.
4. Забери артефакт: `libv2ray-android-arm64-no-xudp / libv2ray.aar`.

### Сборка под другие ABI

В шаге `gomobile bind` замени `-target=android/arm64` на:
- `-target=android` (все ABI)
- или перечисли нужные, например: `-target=android/arm,android/arm64`.

### Если структура апстрима другая

Скрипт `scripts/clone_and_patch.sh` предполагает, что мобильный go-модуль в `AndroidLibXrayLite/mobile`.
Если у тебя иначе — поменяй переменную `MOBILE_DIR` и, при необходимости, `PKG_NAME`.

### Включение в приложение

Скачай артефакт `libv2ray.aar` и положи в `app/libs/`, затем:

```kotlin
dependencies {
    implementation(files("libs/libv2ray.aar"))
}
