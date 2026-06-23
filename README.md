# PONECHAK Tester (нативная iOS-апка)

Нативное приложение для проверки функций, которые **не может веб** (Safari):
- **каждый микрофон по отдельности** (нижний / фронтальный / задний) через `AVAudioSession`
- **Face ID / Touch ID**
- **вибрация**
- **кнопки громкости**

Собирается бесплатно на GitHub Actions, подписывается бесплатным Apple ID через Sideloadly.

## Как получить и поставить (бесплатно, без $99)

### 1. Собрать .ipa на GitHub
1. Создай репозиторий на GitHub, залей в него содержимое этой папки.
2. Открой вкладку **Actions** → workflow **«Build unsigned IPA»** запустится сам (или жми **Run workflow**).
3. По завершении скачай артефакт **PonechakTester-unsigned-ipa** (это `PonechakTester-unsigned.ipa`).

> Сертификат Apple для сборки НЕ нужен — `.ipa` неподписанный.

### 2. Подписать и поставить через Sideloadly (Windows)
1. Поставь **Sideloadly** (https://sideloadly.io) и **Apple Devices/iTunes** (драйвер USB).
2. Подключи iPhone, открой Sideloadly, перетащи `PonechakTester-unsigned.ipa`.
3. Введи **бесплатный Apple ID**, нажми **Start** — Sideloadly подпишет и установит апку.

### 3. Один раз на телефоне
- **Доверить разработчика:** Настройки → Основные → VPN и управление устройством → довериться своему Apple ID.
- **Включить Developer Mode** (iOS 16+): Настройки → Конфиденциальность и безопасность → Режим разработчика → ВКЛ → перезагрузка.

После этого апка запускается и гоняет тесты. Подпись живёт **7 дней** — для «поставил-протестил-стёр» этого хватает.

## Локальная сборка (если появится Mac)
```bash
brew install xcodegen
cd tester-app && xcodegen generate
open PonechakTester.xcodeproj
```

## Структура
- `Sources/` — Swift-исходники (UI + тестеры)
- `project.yml` — спецификация XcodeGen (генерит .xcodeproj)
- `.github/workflows/build.yml` — сборка неподписанного .ipa
