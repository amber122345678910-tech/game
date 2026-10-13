package ru.amigo.chat;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.res.AssetManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.speech.RecognizerIntent;
import android.speech.tts.TextToSpeech;
import android.speech.tts.UtteranceProgressListener;
import android.util.Base64;
import android.view.ViewGroup;
import android.webkit.JavascriptInterface;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.ServiceWorkerClient;
import android.webkit.ServiceWorkerController;
import android.webkit.URLUtil;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import org.json.JSONObject;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/**
 * Амиго для Android: один экран с WebView, в котором открыт index.html из assets.
 *
 * Страница живёт на «настоящем» https-адресе https://appassets.androidplatform.net/ (этот домен
 * Android зарезервировал как раз для файлов приложения; запросы к нему не уходят в сеть), поэтому
 * localStorage и IndexedDB работают как в обычном браузере. Всё остальное (Википедия, погода, Claude)
 * идёт в интернет как обычно.
 *
 * В WebView нет Web Speech API, поэтому голос и микрофон даёт мост window.AmigoAndroid (см. README.md).
 */
public class MainActivity extends Activity {

    static final String HOST = "appassets.androidplatform.net";
    static final String START_URL = "https://" + HOST + "/index.html";
    static final String BRIDGE = "AmigoAndroid";

    private static final int REQ_SPEECH = 1;
    private static final int REQ_SAVE = 2;
    private static final Locale RUSSIAN = new Locale("ru", "RU");
    private static final int MAX_SAVE_BYTES = 20 * 1024 * 1024;

    private WebView web;
    private AssetServer assets;
    private boolean pageReady;
    private final List<String> pendingJs = new ArrayList<>();

    private TextToSpeech tts;
    private final CountDownLatch ttsInit = new CountDownLatch(1);
    /** 0 — ещё запускается, 1 — готов и умеет по-русски, -1 — озвучки нет. */
    private volatile int ttsState;
    private int utteranceSeq;

    private boolean listening;
    private byte[] pendingSaveData;
    private String pendingSaveName;

    // ---------------------------------------------------------------- жизненный цикл

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        assets = new AssetServer(getAssets());
        initTts();
        if ((getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            WebView.setWebContentsDebuggingEnabled(true);
        }
        ServiceWorkerController.getInstance().setServiceWorkerClient(new ServiceWorkerClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebResourceRequest request) {
                return assets.serve(request.getUrl());
            }
        });
        createWebView();
        if (state == null || web.restoreState(state) == null) web.loadUrl(START_URL);
    }

    @SuppressLint({"SetJavaScriptEnabled", "AddJavascriptInterface"})
    private void createWebView() {
        web = new WebView(this);
        web.setBackgroundColor(getColor(R.color.amigo_bg));
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        enableDatabase(s);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        s.setSupportMultipleWindows(false);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        s.setUserAgentString(s.getUserAgentString() + " AmigoAndroid/" + versionName());
        web.setWebViewClient(new Client());
        web.setWebChromeClient(new WebChromeClient());
        web.setDownloadListener((url, userAgent, disposition, mimeType, length) -> onDownload(url, disposition, mimeType));
        web.addJavascriptInterface(new Bridge(), BRIDGE);
        setContentView(web);
    }

    @SuppressWarnings("deprecation")
    private static void enableDatabase(WebSettings s) {
        s.setDatabaseEnabled(true);
    }

    @Override
    protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        if (web != null) web.saveState(out);
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (web != null) web.onResume();
    }

    @Override
    protected void onPause() {
        if (web != null) web.onPause();
        super.onPause();
    }

    @Override
    protected void onStop() {
        // ушли с экрана — Амиго замолкает
        if (tts != null && ttsState == 1) tts.stop();
        super.onStop();
    }

    @Override
    protected void onDestroy() {
        if (tts != null) {
            tts.shutdown();
            tts = null;
        }
        destroyWebView();
        super.onDestroy();
    }

    private void destroyWebView() {
        if (web == null) return;
        ViewGroup parent = (ViewGroup) web.getParent();
        if (parent != null) parent.removeView(web);
        web.destroy();
        web = null;
    }

    /** «Назад»: сначала спросить страницу (закрыть панель/игру), потом история WebView, потом выход. */
    @Override
    @SuppressWarnings("deprecation")
    public void onBackPressed() {
        if (web == null) {
            finish();
            return;
        }
        if (!pageReady) {
            goBackOrFinish();
            return;
        }
        web.evaluateJavascript(
                "(function(){try{return !!(window.amigoOnBack&&window.amigoOnBack()===true)}catch(e){return false}})()",
                handled -> {
                    if (!"true".equals(handled)) goBackOrFinish();
                });
    }

    private void goBackOrFinish() {
        if (web != null && web.canGoBack()) web.goBack();
        else finish();
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQ_SPEECH) {
            listening = false;
            String text = null;
            if (resultCode == RESULT_OK && data != null) {
                ArrayList<String> results = data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS);
                if (results != null && !results.isEmpty()) text = results.get(0);
            }
            boolean empty = text == null || text.trim().isEmpty();
            runJs("window.amigoOnSpeech&&window.amigoOnSpeech(" + (empty ? "null" : jsString(text.trim())) + ")");
        } else if (requestCode == REQ_SAVE) {
            byte[] bytes = pendingSaveData;
            String name = pendingSaveName;
            pendingSaveData = null;
            pendingSaveName = null;
            boolean ok = false;
            if (resultCode == RESULT_OK && data != null && data.getData() != null && bytes != null) {
                try (OutputStream os = getContentResolver().openOutputStream(data.getData())) {
                    if (os != null) {
                        os.write(bytes);
                        ok = true;
                    }
                } catch (IOException | SecurityException e) {
                    ok = false;
                }
                toast(ok ? "Файл сохранён: " + name : "Не получилось сохранить файл");
            }
            reportSaved(ok, name);
        }
    }

    // ---------------------------------------------------------------- WebView

    private final class Client extends WebViewClient {
        @Override
        public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
            return assets.serve(request.getUrl());
        }

        @Override
        public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
            Uri uri = request.getUrl();
            if (isLocal(uri)) return false;
            String scheme = uri.getScheme() == null ? "" : uri.getScheme().toLowerCase(Locale.ROOT);
            switch (scheme) {
                case "about":
                case "blob":
                case "data":
                case "javascript":
                    return false;
                case "http":
                case "https":
                    // встроенные фреймы пусть грузятся; переход всей страницы — во внешний браузер
                    if (!request.isForMainFrame()) return false;
                    break;
                default:
                    break;
            }
            openExternal(uri);
            return true;
        }

        @Override
        public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
            pageReady = false;
        }

        @Override
        public void onPageFinished(WebView view, String url) {
            if (view != web) return;
            pageReady = true;
            // запоминаем имя файла из <a download="…">, чтобы сохранить blob: под правильным именем
            view.evaluateJavascript("if(!window.__amigoDl){window.__amigoDl=1;document.addEventListener('click',function(e){"
                    + "var a=e.target&&e.target.closest&&e.target.closest('a[download]');"
                    + "if(a)window.__amigoDlName=a.getAttribute('download')||''},true)}", null);
            for (String js : pendingJs) view.evaluateJavascript(js, null);
            pendingJs.clear();
        }

        @Override
        public boolean onRenderProcessGone(WebView view, RenderProcessGoneDetail detail) {
            // Система убила движок страницы (например, не хватило памяти): пересоздаём экран, а не падаем.
            if (view == web) {
                destroyWebView();
                recreate();
            }
            return true;
        }
    }

    static boolean isLocal(Uri uri) {
        return uri != null && "https".equalsIgnoreCase(uri.getScheme()) && HOST.equalsIgnoreCase(uri.getHost());
    }

    private void openExternal(Uri uri) {
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE));
        } catch (ActivityNotFoundException | SecurityException e) {
            toast("Не нашлось приложения, чтобы открыть ссылку");
        }
    }

    private void onDownload(String url, String disposition, String mimeType) {
        if (url == null) return;
        if (url.startsWith("blob:") || url.startsWith("data:")) {
            // Содержимое blob: есть только внутри страницы — пусть она сама прочитает его и отдаст мосту.
            String fallback = URLUtil.guessFileName(url, disposition, mimeType);
            runJs("(function(u,n){fetch(u).then(function(r){return r.blob()}).then(function(b){return new Promise(function(ok,no){"
                    + "var f=new FileReader();f.onload=function(){ok(f.result)};f.onerror=no;f.readAsDataURL(b)})}).then(function(d){"
                    + BRIDGE + ".saveDataUrl(n,d)},function(){" + BRIDGE + ".saveDataUrl(n,'')})})("
                    + jsString(url) + ",window.__amigoDlName||" + jsString(fallback) + ");window.__amigoDlName=''");
        } else {
            openExternal(Uri.parse(url));
        }
    }

    /** Выполнить JS на странице (из любого потока); если страница ещё грузится — после загрузки. */
    void runJs(String js) {
        runOnUiThread(() -> {
            if (web == null) return;
            if (pageReady) web.evaluateJavascript(js, null);
            else pendingJs.add(js);
        });
    }

    static String jsString(String s) {
        return JSONObject.quote(s).replace("\u2028", "\\u2028").replace("\u2029", "\\u2029");
    }

    private void toast(String text) {
        runOnUiThread(() -> Toast.makeText(this, text, Toast.LENGTH_LONG).show());
    }

    // ---------------------------------------------------------------- голос (TextToSpeech)

    private void initTts() {
        try {
            tts = new TextToSpeech(getApplicationContext(), status -> {
                int state = -1;
                TextToSpeech engine = tts;
                if (status == TextToSpeech.SUCCESS && engine != null) {
                    int lang = engine.setLanguage(RUSSIAN);
                    if (lang >= TextToSpeech.LANG_AVAILABLE) {
                        engine.setPitch(1.1f);
                        engine.setOnUtteranceProgressListener(new SpeechProgress());
                        state = 1;
                    }
                }
                ttsState = state;
                ttsInit.countDown();
            });
        } catch (RuntimeException e) {
            ttsState = -1;
            ttsInit.countDown();
        }
    }

    private boolean ttsReady(long waitMs) {
        if (ttsState == 0) {
            try {
                ttsInit.await(waitMs, TimeUnit.MILLISECONDS);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
        return ttsState == 1 && tts != null;
    }

    private final class SpeechProgress extends UtteranceProgressListener {
        @Override
        public void onStart(String id) {
            speaking(true);
        }

        @Override
        public void onDone(String id) {
            if (id.endsWith(":last")) speaking(false);
        }

        @Override
        @SuppressWarnings("deprecation")
        public void onError(String id) {
            speaking(false);
        }

        @Override
        public void onError(String id, int errorCode) {
            speaking(false);
        }

        @Override
        public void onStop(String id, boolean interrupted) {
            speaking(false);
        }
    }

    private void speaking(boolean on) {
        runJs("window.amigoOnSpeaking&&window.amigoOnSpeaking(" + on + ")");
    }

    private void speakNow(String text, float rate) {
        float r = (rate > 0f && !Float.isNaN(rate)) ? Math.max(0.3f, Math.min(rate, 3f)) : 1f;
        TextToSpeech engine = tts;
        if (engine == null) return;
        engine.setSpeechRate(r);
        List<String> parts = split(text, Math.min(3900, TextToSpeech.getMaxSpeechInputLength() - 1));
        int seq;
        synchronized (this) {
            seq = ++utteranceSeq;
        }
        for (int i = 0; i < parts.size(); i++) {
            String id = "amigo" + seq + ":" + i + (i == parts.size() - 1 ? ":last" : "");
            engine.speak(parts.get(i), i == 0 ? TextToSpeech.QUEUE_FLUSH : TextToSpeech.QUEUE_ADD, null, id);
        }
    }

    /** Длинный текст режем по предложениям: у движка озвучки есть предел длины одной фразы. */
    static List<String> split(String text, int max) {
        List<String> out = new ArrayList<>();
        String rest = text;
        while (rest.length() > max) {
            int cut = -1;
            for (String sep : new String[]{". ", "! ", "? ", "\n", "; ", ", ", " "}) {
                int at = rest.lastIndexOf(sep, max - sep.length());
                if (at > max / 3) {
                    cut = at + sep.length();
                    break;
                }
            }
            if (cut <= 0) cut = max;
            out.add(rest.substring(0, cut).trim());
            rest = rest.substring(cut);
        }
        if (!rest.trim().isEmpty() || out.isEmpty()) out.add(rest.trim());
        return out;
    }

    // ---------------------------------------------------------------- сохранение файлов

    private boolean saveBytes(String rawName, String mimeType, byte[] data) {
        String name = cleanFileName(rawName);
        String mime = (mimeType == null || mimeType.trim().isEmpty()) ? "application/octet-stream" : mimeType.trim();
        if (Build.VERSION.SDK_INT >= 29) {
            ContentResolver cr = getContentResolver();
            ContentValues v = new ContentValues();
            v.put(MediaStore.MediaColumns.DISPLAY_NAME, name);
            v.put(MediaStore.MediaColumns.MIME_TYPE, mime);
            v.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS);
            v.put(MediaStore.MediaColumns.IS_PENDING, 1);
            Uri uri = null;
            try {
                uri = cr.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v);
                if (uri == null) throw new IOException("insert failed");
                try (OutputStream os = cr.openOutputStream(uri)) {
                    if (os == null) throw new IOException("no stream");
                    os.write(data);
                }
                v.clear();
                v.put(MediaStore.MediaColumns.IS_PENDING, 0);
                cr.update(uri, v, null, null);
                toast("Файл сохранён в «Загрузки»: " + name);
                reportSaved(true, name);
                return true;
            } catch (IOException | RuntimeException e) {
                if (uri != null) {
                    try {
                        cr.delete(uri, null, null);
                    } catch (RuntimeException ignored) {
                        // нечего удалять
                    }
                }
                toast("Не получилось сохранить файл");
                reportSaved(false, name);
                return false;
            }
        }
        // Android 7–9: системное окно «Сохранить как» (без лишних разрешений)
        runOnUiThread(() -> {
            pendingSaveData = data;
            pendingSaveName = name;
            Intent i = new Intent(Intent.ACTION_CREATE_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType(mime)
                    .putExtra(Intent.EXTRA_TITLE, name);
            try {
                startActivityForResult(i, REQ_SAVE);
            } catch (ActivityNotFoundException e) {
                pendingSaveData = null;
                pendingSaveName = null;
                toast("Не получилось сохранить файл");
                reportSaved(false, name);
            }
        });
        return true;
    }

    private void reportSaved(boolean ok, String name) {
        runJs("window.amigoOnSaved&&window.amigoOnSaved(" + ok + "," + jsString(name == null ? "" : name) + ")");
    }

    static String cleanFileName(String name) {
        String n = name == null ? "" : name.replaceAll("[\\\\/:*?\"<>|\\x00-\\x1f]+", "_").trim();
        if (n.isEmpty() || n.startsWith(".")) n = "amigo" + n;
        return n.length() > 120 ? n.substring(n.length() - 120) : n;
    }

    // ---------------------------------------------------------------- версия

    @SuppressWarnings("deprecation")
    String versionName() {
        try {
            PackageManager pm = getPackageManager();
            PackageInfo info = Build.VERSION.SDK_INT >= 33
                    ? pm.getPackageInfo(getPackageName(), PackageManager.PackageInfoFlags.of(0))
                    : pm.getPackageInfo(getPackageName(), 0);
            return info.versionName == null ? "" : info.versionName;
        } catch (PackageManager.NameNotFoundException e) {
            return "";
        }
    }

    // ---------------------------------------------------------------- мост для страницы

    /** window.AmigoAndroid — методы вызываются из JS (в отдельном потоке Java). */
    final class Bridge {

        /** Прочитать текст вслух по-русски. rate — как SpeechSynthesisUtterance.rate (1 = обычная скорость). */
        @JavascriptInterface
        public void speak(String text, float rate) {
            if (text == null || text.trim().isEmpty()) return;
            if (!ttsReady(2500)) return;
            speakNow(text.trim(), rate);
        }

        @JavascriptInterface
        public void stopSpeaking() {
            TextToSpeech engine = tts;
            if (engine != null && ttsState == 1) engine.stop();
        }

        /** Есть ли русская озвучка. В первые мгновения после запуска ждёт движок до 1,5 с. */
        @JavascriptInterface
        public boolean canSpeak() {
            return ttsReady(1500);
        }

        /** Запустить системное распознавание речи (ru-RU). Ответ придёт в window.amigoOnSpeech(text|null). */
        @JavascriptInterface
        public void listen() {
            runOnUiThread(() -> {
                if (listening) return;
                TextToSpeech engine = tts;
                if (engine != null && ttsState == 1) engine.stop();
                Intent i = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                        .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                        .putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ru-RU")
                        .putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "ru-RU")
                        .putExtra(RecognizerIntent.EXTRA_PROMPT, "Говори, я слушаю…")
                        .putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1);
                try {
                    startActivityForResult(i, REQ_SPEECH);
                    listening = true;
                } catch (ActivityNotFoundException | SecurityException e) {
                    runJs("window.amigoOnSpeech&&window.amigoOnSpeech(null)");
                }
            });
        }

        /** Есть ли на телефоне приложение, которое умеет распознавать речь (обычно это Google). */
        @JavascriptInterface
        public boolean canListen() {
            return new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).resolveActivity(getPackageManager()) != null;
        }

        @JavascriptInterface
        public String version() {
            return versionName();
        }

        /**
         * Сохранить текстовый файл (например, игру .html) в «Загрузки».
         * Android 10+: сразу, Android 7–9: через окно «Сохранить как».
         * Итог придёт в window.amigoOnSaved(ok, name).
         */
        @JavascriptInterface
        public boolean saveFile(String filename, String mimeType, String content) {
            if (content == null) return false;
            byte[] bytes = content.getBytes(StandardCharsets.UTF_8);
            if (bytes.length > MAX_SAVE_BYTES) return false;
            return saveBytes(filename, mimeType, bytes);
        }

        /** То же для data:-URL (так обёртка сохраняет ссылки blob: с атрибутом download). */
        @JavascriptInterface
        public boolean saveDataUrl(String filename, String dataUrl) {
            if (dataUrl == null || !dataUrl.startsWith("data:")) {
                toast("Не получилось скачать файл");
                reportSaved(false, filename);
                return false;
            }
            int comma = dataUrl.indexOf(',');
            if (comma < 0) return false;
            String meta = dataUrl.substring(5, comma);
            String mime = meta.split(";", 2)[0];
            byte[] bytes;
            try {
                bytes = meta.endsWith(";base64")
                        ? Base64.decode(dataUrl.substring(comma + 1), Base64.DEFAULT)
                        : Uri.decode(dataUrl.substring(comma + 1)).getBytes(StandardCharsets.UTF_8);
            } catch (IllegalArgumentException e) {
                return false;
            }
            if (bytes.length > MAX_SAVE_BYTES) return false;
            return saveBytes(filename, mime, bytes);
        }
    }

    // ---------------------------------------------------------------- файлы из assets по https

    /** Отдаёт assets/<путь> на адрес https://appassets.androidplatform.net/<путь>. */
    static final class AssetServer {
        private static final Map<String, String> MIME = new HashMap<>();

        static {
            MIME.put("html", "text/html");
            MIME.put("htm", "text/html");
            MIME.put("js", "text/javascript");
            MIME.put("mjs", "text/javascript");
            MIME.put("css", "text/css");
            MIME.put("json", "application/json");
            MIME.put("webmanifest", "application/manifest+json");
            MIME.put("txt", "text/plain");
            MIME.put("svg", "image/svg+xml");
            MIME.put("png", "image/png");
            MIME.put("jpg", "image/jpeg");
            MIME.put("jpeg", "image/jpeg");
            MIME.put("gif", "image/gif");
            MIME.put("webp", "image/webp");
            MIME.put("ico", "image/x-icon");
            MIME.put("woff", "font/woff");
            MIME.put("woff2", "font/woff2");
            MIME.put("ttf", "font/ttf");
            MIME.put("otf", "font/otf");
            MIME.put("mp3", "audio/mpeg");
            MIME.put("ogg", "audio/ogg");
            MIME.put("wav", "audio/wav");
            MIME.put("mp4", "video/mp4");
            MIME.put("webm", "video/webm");
            MIME.put("wasm", "application/wasm");
        }

        private final AssetManager am;

        AssetServer(AssetManager am) {
            this.am = am;
        }

        WebResourceResponse serve(Uri uri) {
            if (!isLocal(uri)) return null; // чужие адреса — в сеть как обычно
            String path = uri.getPath();
            if (path == null || path.isEmpty() || "/".equals(path)) path = "/index.html";
            path = path.substring(1);
            if (path.contains("..") || path.startsWith("/")) return status(404, "Not Found");
            InputStream in;
            try {
                in = am.open(path, AssetManager.ACCESS_STREAMING);
            } catch (IOException e) {
                return status(404, "Not Found");
            }
            String mime = mimeOf(path);
            boolean text = mime.startsWith("text/") || mime.endsWith("json") || mime.endsWith("+xml") || mime.endsWith("javascript");
            Map<String, String> headers = new HashMap<>();
            headers.put("Cache-Control", "no-cache");
            headers.put("X-Content-Type-Options", "nosniff");
            return new WebResourceResponse(mime, text ? "UTF-8" : null, 200, "OK", headers, in);
        }

        static String mimeOf(String path) {
            int dot = path.lastIndexOf('.');
            String ext = dot < 0 ? "" : path.substring(dot + 1).toLowerCase(Locale.ROOT);
            String mime = MIME.get(ext);
            return mime != null ? mime : "application/octet-stream";
        }

        private static WebResourceResponse status(int code, String reason) {
            Map<String, String> headers = new HashMap<>();
            headers.put("Cache-Control", "no-cache");
            return new WebResourceResponse("text/plain", "UTF-8", code, reason, headers,
                    new ByteArrayInputStream(reason.getBytes(StandardCharsets.UTF_8)));
        }
    }
}
