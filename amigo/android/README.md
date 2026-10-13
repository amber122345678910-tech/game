# Амиго для Android

Маленькое Android-приложение (APK ≈ 0,6 МБ), внутри которого открывается тот же `amigo/index.html`.
Это обёртка WebView **без сторонних библиотек** (ни AndroidX, ни Kotlin) — только стандартный Android API.
Работает без интернета; Википедия, погода, Claude и шрифты Google подключаются, когда сеть есть.

- пакет `ru.amigo.chat`, название «Амиго», версия `2.0` (код `2`)
- Android 7.0+ (`minSdk 24`), `targetSdk 34`
- разрешения: `INTERNET`, `ACCESS_NETWORK_STATE` (для `navigator.onLine`), `VIBRATE` (для `navigator.vibrate`) —
  все «обычные», телефон ничего не спрашивает. Микрофон приложению не нужен: речь распознаёт
  системное окно Google.

## Сборка

```bash
cd amigo/android
./build.sh          # через Gradle + Android Gradle Plugin
./build.sh --sdk    # без Gradle: напрямую aapt2 + javac + d8 + zipalign + apksigner
```

Результат: **`amigo/Amigo.apk`** (release, подписан ключом `amigo-release.jks`, сразу проверяется `apksigner verify`).
Перед сборкой скрипт кладёт в APK свежие `../index.html`, `../manifest.webmanifest` и `../icons/*.png|svg` —
то есть после `node tools/build.js` достаточно снова запустить `./build.sh`. Копии `index.html` в репозитории нет:
Gradle собирает её в `app/build/generated/amigo-assets`, а `--sdk` — в `build/sdk/assets`.

Нужно: JDK 17+ и Android SDK с `platforms;android-34` и `build-tools;35.0.0` (для `--sdk` подойдут и 34.0.0).
SDK ищется в `$ANDROID_HOME`, `local.properties`, `/root/android-sdk`, `~/Android/Sdk`. Gradle берётся из `PATH`,
`/opt/gradle` или `./gradlew` (Gradle 8.14.3, AGP 8.13.2). Другие настройки — в начале `build.sh`.

Можно открыть папку `amigo/android` в Android Studio и нажать Run — всё то же самое.

Версию меняйте в `app/build.gradle` (`versionCode` нужно увеличивать при каждом выпуске, иначе телефон
не поставит обновление). `build.sh --sdk` читает версии оттуда же.

## Как поставить на телефон

1. Скопируйте `Amigo.apk` на телефон (через кабель, мессенджер, Google Диск — как удобно) и откройте его.
2. Телефон спросит, можно ли этому приложению (браузеру, «Файлам») ставить программы — разрешите.
3. Готово: на экране появится Амиго.

Обновление — так же: новый `Amigo.apk`, подписанный **тем же ключом** и с бо́льшим `versionCode`,
ставится поверх, все разговоры и настройки сохраняются. Если удалить приложение, его данные
(localStorage) тоже удалятся. Данные приложения отдельны от данных браузера.

## Ключ подписи

`amigo-release.jks` — PKCS12, псевдоним `amigo`, пароль `amigo123` (и для хранилища, и для ключа).

Это хобби-приложение, которое раздаётся файлом APK, поэтому ключ нарочно лежит прямо в репозитории:
так любой компьютер соберёт APK, который встанет **поверх** уже установленного (Android разрешает
обновление, только если подпись та же). Минус: кто угодно с доступом к репозиторию может подписать
«обновление» Амиго — для семейного приложения это нормально.

**Для Google Play так нельзя.** Сделайте свой секретный ключ, не кладите его в git и подключите
Play App Signing:

```bash
keytool -genkeypair -keystore my-upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
```

(и пропишите его в `signingConfigs` в `app/build.gradle`). Учтите, что приложение с другой подписью
не встанет поверх старого — его придётся удалить (вместе с данными). Для Play также понадобится
`targetSdk 35+`, а с ним — отрисовка «от края до края» (edge-to-edge), см. «Ограничения».

## Как устроено

- `index.html` и остальное из `assets/` отдаются через `WebViewClient.shouldInterceptRequest` по адресу
  **`https://appassets.androidplatform.net/<путь>`** (`/` → `index.html`) с правильными MIME-типами и UTF-8.
  Этот домен Android зарезервировал для файлов приложений, запросы к нему никогда не уходят в интернет;
  а раз адрес настоящий `https`, у страницы нормальный защищённый origin и работают localStorage / IndexedDB.
  Всех остальных адресов обёртка не трогает — они идут в сеть как обычно.
- Ссылки на другие сайты (в том числе `target="_blank"`, `mailto:`, `tel:`) открываются в браузере телефона.
- Кнопка «Назад»: сначала спрашивает страницу `window.amigoOnBack()` (см. ниже), потом история WebView, потом выход.
- Цвет полосок статуса и навигации — как фон приложения: `#EDF2F0` в светлой теме и `#0C1715` в тёмной
  (`values/`, `values-night/`, `values-v27/themes.xml`). Тема Android светлая/тёмная — как в системе,
  и WebView передаёт её странице через `prefers-color-scheme`. Страница не залезает под вырез камеры и
  системные полоски (обычная раскладка без edge-to-edge), поэтому `env(safe-area-inset-*)` там равны 0.
- Поворот экрана не перезапускает страницу (`configChanges`), клавиатура сжимает экран (`adjustResize`).
- Если система убьёт движок страницы (мало памяти), приложение не падает, а открывает страницу заново.
- `sw.js` в APK нарочно не кладётся: всё и так лежит внутри приложения, а service worker с кэшем после
  обновления APK показывал бы старую версию. Регистрация `sw.js` в приложении просто получит 404 —
  лучше вообще не регистрировать его, если есть `window.AmigoAndroid`.
- Скачивание: ссылки `blob:`/`data:` с атрибутом `download` (кнопка «⬇️ Скачать игру») обёртка сохраняет
  в «Загрузки» сама; можно и напрямую через `AmigoAndroid.saveFile(...)`.

## Мост `window.AmigoAndroid`

В Android WebView нет Web Speech API (`speechSynthesis`, `SpeechRecognition`), поэтому голос и микрофон
даёт объект `window.AmigoAndroid` (он есть с самого начала загрузки страницы; ещё в User-Agent
дописано `AmigoAndroid/2.0`). Методы синхронные с точки зрения JS; результат распознавания приходит позже,
через функцию, которую страница кладёт в `window`.

| Метод | Что делает |
|---|---|
| `AmigoAndroid.speak(text: string, rate: number): void` | Читает текст вслух по-русски (Android TextToSpeech, `ru-RU`). Прерывает то, что звучало. `rate` — как у `SpeechSynthesisUtterance.rate`: `1` — обычная скорость (допустимо 0.3–3). Длинный текст режется на фразы сам. |
| `AmigoAndroid.stopSpeaking(): void` | Замолчать. |
| `AmigoAndroid.canSpeak(): boolean` | Есть ли русская озвучка. Сразу после запуска может подождать движок до 1,5 с. `false`, если движка нет или нет русского голоса. |
| `AmigoAndroid.listen(): void` | Открывает системное окно распознавания речи (`RecognizerIntent`, `ru-RU`). Результат — в `window.amigoOnSpeech`. |
| `AmigoAndroid.canListen(): boolean` | Есть ли на телефоне распознавание речи (обычно приложение Google). |
| `AmigoAndroid.version(): string` | Версия приложения, например `"2.0"`. |
| `AmigoAndroid.saveFile(filename: string, mimeType: string, content: string): boolean` | Сохраняет текстовый файл (UTF-8) в «Загрузки» (Android 10+ сразу, Android 7–9 — через окно «Сохранить как»). Итог — в `window.amigoOnSaved`. Возвращает `false`, если сохранение даже не началось. |
| `AmigoAndroid.saveDataUrl(filename: string, dataUrl: string): boolean` | То же для `data:`-URL (так обёртка сама сохраняет `blob:`-скачивания). |

Функции, которые страница может объявить (все необязательные):

| Функция | Когда вызывается |
|---|---|
| `window.amigoOnSpeech(text)` | После `listen()`: `text` — распознанная строка, или `null`, если ничего не услышано, отменено или ошибка. |
| `window.amigoOnSpeaking(on)` | `true`, когда начала звучать речь, `false`, когда закончилась/остановлена (для анимации рта). |
| `window.amigoOnSaved(ok, filename)` | Итог `saveFile` / скачивания. Короткое сообщение на экране обёртка показывает сама. |
| `window.amigoOnBack()` | При нажатии «Назад». Вернуть `true`, если страница сама обработала нажатие (закрыла панель/игру); иначе — назад по истории или выход из приложения. |

Пример подключения:

```js
const A = window.AmigoAndroid;
if (A) {
  // голос
  if (A.canSpeak()) { /* показать кнопку голоса */ }
  speak = plain => A.speak(plain, settings.rate || 1);
  stop = () => A.stopSpeaking();
  window.amigoOnSpeaking = on => avatar.classList.toggle('talk', on);
  // микрофон
  if (A.canListen()) {
    micBtn.hidden = false;
    micBtn.onclick = () => { micBtn.classList.add('listening'); A.listen(); };
    window.amigoOnSpeech = text => { micBtn.classList.remove('listening'); if (text) send(text); };
  }
}
```

## Ограничения

- Нет эмулятора в сборочной среде — APK проверен сборкой, `apksigner verify`, `aapt2 dump badging`,
  `javac -Xlint:all` и Android Lint (замечаний нет), но не запускался на живом телефоне.
- Голос: нужен движок озвучки с русским голосом (на большинстве телефонов это Google «Синтез речи»;
  если голоса нет — `canSpeak()` вернёт `false`, голос можно скачать в настройках телефона).
- Микрофон: нужен системный распознаватель (`canListen()`); на телефонах без сервисов Google его может не быть.
- `Notification` в WebView нет — уведомлений о таймерах в фоне не будет; таймеры работают, пока приложение живо.
- `targetSdk 34`. Если поднимать до 35+ (это нужно для Google Play), Android 15 включит отрисовку
  «от края до края», и тогда нужно добавить отступы под системные полоски (или временно
  `android:windowOptOutEdgeToEdgeEnforcement`).
- Мост доступен и встроенным фреймам с других сайтов; сейчас Амиго таких не встраивает.

## Иконки

Исходники — `amigo/icons/icon.svg` (обычная) и `amigo/icons/maskable.svg` (лицо внутри безопасной зоны 80%).
PNG для веба и старые значки Android (`res/mipmap-*/ic_launcher*.png`) перерисовываются так:

```bash
NODE_PATH=$(npm root -g) node amigo/icons/render-icons.js   # нужен Playwright с Chromium
```

Значок для Android 8+ — векторный (`res/drawable/ic_launcher_foreground.xml`, `ic_launcher_monochrome.xml`
для «тематических» значков Android 13+) на фоне `#EDF2F0`.

## Файлы

```
android/
  build.sh                     сборка → ../Amigo.apk
  amigo-release.jks            ключ подписи (пароль amigo123)
  settings.gradle, build.gradle, gradle.properties, gradlew, gradle/wrapper/
  app/build.gradle             версии, подпись, копирование ../index.html в assets
  app/src/main/AndroidManifest.xml
  app/src/main/java/ru/amigo/chat/MainActivity.java   WebView, раздача assets, мост AmigoAndroid
  app/src/main/res/            тема и цвета, значки (mipmap-*, adaptive-icon)
```
