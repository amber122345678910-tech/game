// Редактор кода: пишешь Luau, запускаешь, видишь вывод и мир
const Editor = {
  key: null,
  rt: null,
  vp: null,
  resolve: null,
  errLine: null,
  lastOut: [],
  lastErr: null,
  outBuf: [],   // строки вывода, которые ещё не нарисованы
  outRaf: 0,
  keyBtns: {},  // кнопки быстрых клавиш по подписи
};

const KW = new Set("local function end if then else elseif for in do while repeat until return break and or not nil true false".split(" "));
const GLOBALS = new Set("game workspace Workspace script Instance Vector3 Color3 BrickColor CFrame Enum print warn wait task math table string tostring tonumber pairs ipairs TweenService TweenInfo Players".split(" "));

function escHtml(s) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function highlight(src) {
  let out = "";
  let i = 0;
  const n = src.length;
  while (i < n) {
    const c = src[i];
    if (c === "-" && src[i + 1] === "-") {
      let j = src.indexOf("\n", i);
      if (j < 0) j = n;
      out += `<span class="tc">${escHtml(src.slice(i, j))}</span>`;
      i = j;
    } else if (c === '"' || c === "'") {
      let j = i + 1;
      while (j < n && src[j] !== c && src[j] !== "\n") j += src[j] === "\\" ? 2 : 1;
      j = Math.min(n, j + 1);
      out += `<span class="ts">${escHtml(src.slice(i, j))}</span>`;
      i = j;
    } else if (/[A-Za-z_]/.test(c)) {
      let j = i + 1;
      while (j < n && /[A-Za-z0-9_]/.test(src[j])) j++;
      const w = src.slice(i, j);
      const cls = KW.has(w) ? "tk" : GLOBALS.has(w) ? "tg" : src[j] === "(" ? "tf" : "";
      out += cls ? `<span class="${cls}">${w}</span>` : w;
      i = j;
    } else if (/[0-9]/.test(c)) {
      let j = i + 1;
      while (j < n && /[0-9.xa-fA-F]/.test(src[j])) j++;
      out += `<span class="tn">${src.slice(i, j)}</span>`;
      i = j;
    } else {
      out += escHtml(c);
      i++;
    }
  }
  return out + "\n";
}

function taskList() {
  const s = G.save;
  const list = [{ key: "sandbox", label: "🧪 Песочница (свободный код)" }];
  for (const L of LESSONS) {
    const avail = L.id === "l1" || s.flags["arrived_" + L.zone] || s.practice[L.id];
    if (!avail) continue;
    list.push({ key: "p:" + L.id, label: `${s.practice[L.id] ? "✅" : "📘"} Урок ${L.n}: ${L.title}` });
  }
  for (const L of LESSONS) {
    const st = s.hw[L.homework.id];
    if (!st) continue;
    const icon = st === "done" ? "⭐" : st === "checked" ? "✅" : "📝";
    list.push({ key: "h:" + L.homework.id, label: `${icon} Домашка №${L.n}: ${L.homework.title}` });
  }
  for (const h of s.customHw || []) list.push({ key: "c:" + h.id, label: `${h.status === "done" ? "⭐" : "★"} ${h.title}` });
  return list;
}

function taskFor(key) {
  if (!key || key === "sandbox") return { kind: "sandbox", title: "Песочница", task: "Пиши любой код и запускай. Тут ничего не проверяется — просто экспериментируй!", starter: "-- Песочница: пробуй что хочешь\nprint(\"Привет из песочницы!\")\n", card: sandboxCard() };
  const [t, id] = key.split(":");
  if (t === "p") {
    const L = LESSON[id];
    return { kind: "practice", id, title: `Урок ${L.n}: ${L.title}`, task: L.practice.task, starter: L.practice.starter, hint: L.practice.hint, check: L.practice.check, card: L.card, lesson: L };
  }
  if (t === "h") {
    const H = HOMEWORK[id];
    return { kind: "homework", id, title: `Домашка №${H.lesson.n}: ${H.title}`, task: H.task, starter: H.starter, hint: H.hint, check: H.check, card: H.lesson.card, time: H.time, lesson: H.lesson, review: H.review };
  }
  if (t === "c") {
    const h = (G.save.customHw || []).find((x) => x.id === id);
    if (!h) return taskFor("sandbox");
    return { kind: "custom", id, title: h.title, task: h.task, starter: "-- " + h.title + "\n", hint: h.example || "", card: h.example ? `<p>Пример от Клода:</p><pre>${escHtml(h.example)}</pre>` : "", custom: h };
  }
  return taskFor("sandbox");
}

function sandboxCard() {
  const done = LESSONS.filter((l) => G.save.practice[l.id]);
  if (!done.length) return "<p>Пока нет пройденных уроков. Начни с портал-аппарата в гараже.</p>";
  return "<p>Шпаргалки пройденных уроков:</p>" + done.map((l) => `<details><summary>Урок ${l.n}: ${l.title}</summary>${l.card}</details>`).join("");
}

// задание уже сделано? (урок пройден, домашка сдана, особое задание сдано)
function taskDone(key) {
  const s = G.save;
  const [t, id] = String(key || "").split(":");
  if (t === "p") return !!s.practice[id];
  if (t === "h") return s.hw[id] === "done";
  if (t === "c") {
    const h = (s.customHw || []).find((x) => x.id === id);
    return !h || h.status === "done";
  }
  return false;
}

// первый доступный урок, который ещё не пройден
function nextLessonKey() {
  const t = taskList().find((x) => x.key.startsWith("p:") && !G.save.practice[x.key.slice(2)]);
  return t ? t.key : null;
}

// что открыть по кнопке </>: домашка, которую ждёт Клод → непройденный урок → прошлое несделанное → песочница
function defaultTask() {
  syncHomework();
  const hid = pendingHw();
  if (hid) return "h:" + hid;
  const last = G.save.lastTask;
  const keys = taskList().map((t) => t.key);
  const openLast = last && last !== "sandbox" && keys.includes(last) && !taskDone(last);
  if (openLast && !last.startsWith("h:")) return last;
  return nextLessonKey() || (openLast ? last : "sandbox");
}

function openEditor(key) {
  return new Promise((resolve) => {
    if (Editor.resolve) Editor.resolve();
    Editor.resolve = resolve;
    const el = document.getElementById("editor");
    el.hidden = false;
    G.overlay = "editor";
    // без ключа: сначала открываем домашку, которую ждёт Клод, а не старый урок
    key = key || defaultTask();
    if (!taskList().some((t) => t.key === key)) key = "sandbox";
    loadTask(key);
    fitSheet();
  });
}

// закрыть редактор и сразу показать домашку Клоду
function showToClaude() {
  closeEditor();
  if (G.mode !== "world" || Battle.active) return;
  if (!G.sceneQueue.includes(showHomework)) runScene(showHomework);
}

function switchTask(key) {
  stopRun();
  loadTask(key);
}

// перенести код в домашку и сразу проверить.
// fromKey — если код лежал в другой домашке, та снова становится пустой заготовкой
function carryToHw(hid, code, fromKey) {
  stopRun();
  if (fromKey && fromKey.startsWith("h:") && fromKey !== "h:" + hid) G.save.code[fromKey] = taskFor(fromKey).starter || "";
  G.save.code["h:" + hid] = code;
  loadTask("h:" + hid);
  checkTask();
}

function closeEditor() {
  stopRun();
  // окно «Мир» больше не рисуем — бережём батарею
  if (Editor.vp) Editor.vp.stop();
  document.getElementById("editor").hidden = true;
  G.overlay = null;
  saveSoon();
  const r = Editor.resolve;
  Editor.resolve = null;
  if (r) r();
}

function fillTaskSelect(key) {
  const sel = document.getElementById("edTask");
  sel.innerHTML = "";
  for (const t of taskList()) {
    const o = document.createElement("option");
    o.value = t.key;
    o.textContent = t.label;
    if (t.key === key) o.selected = true;
    sel.appendChild(o);
  }
}

// ярлык: какое задание открыто
const KIND_TAGS = {
  practice: ["УРОК", "var(--good)"],
  homework: ["ДОМАШКА", "var(--gold)"],
  custom: ["ОСОБОЕ ЗАДАНИЕ", "var(--claude)"],
  sandbox: ["ПЕСОЧНИЦА", "#8ad8ff"],
};
function kindTag(kind) {
  const [text, color] = KIND_TAGS[kind] || KIND_TAGS.sandbox;
  return `<span class="edKind" style="display:inline-block;margin:0 6px 3px 0;padding:3px 5px 2px;border:2px solid ${color};color:${color};font-family:var(--display);font-size:9px;line-height:1.2;vertical-align:middle">${text}</span>`;
}
function taskStatus(T) {
  const s = G.save;
  if (T.kind === "practice") return s.practice[T.id] ? "✅ пройден" : "";
  if (T.kind === "homework") return { given: "📝 задана", checked: "✅ проверена", done: "⭐ сдана" }[s.hw[T.id]] || "";
  if (T.kind === "custom") return { ready: "✅ готово", done: "⭐ сдано" }[T.custom.status] || "";
  return "";
}

function renderTaskHead(T, noNote) {
  const st = taskStatus(T);
  document.getElementById("edTaskText").innerHTML = `${kindTag(T.kind)}<b>${escHtml(T.title)}</b>${st ? ` <span class="dim" style="white-space:nowrap">${st}</span>` : ""}<br>${escHtml(T.task)}`;
  if (!noNote) taskNote(T);
}

// плашка сверху задания с кнопкой (кнопки может и не быть)
function setNote(text, btn, fn, good) {
  const box = document.getElementById("edTaskText");
  let el = document.getElementById("edNote");
  if (!el) {
    el = document.createElement("div");
    el.id = "edNote";
    box.prepend(el);
  }
  const c = good ? "var(--good)" : "var(--gold)";
  el.style.cssText = `margin:0 0 6px;padding:4px 8px 6px;border:2px solid ${c};color:${c}`;
  el.textContent = text + " ";
  if (btn) {
    const b = document.createElement("button");
    b.type = "button";
    b.className = "pill";
    b.style.cssText = "margin-top:4px;color:var(--ink)";
    b.textContent = btn;
    b.onclick = fn;
    el.appendChild(b);
  }
  const top = document.querySelector(".edTop");
  if (top) top.scrollTop = 0;
}

// что делать дальше: { label, fn } для кнопки
function nextStep() {
  const hid = pendingHw();
  if (hid) {
    const n = HOMEWORK[hid].lesson.n;
    return G.save.hw[hid] === "checked" ? { label: `📜 Показать Домашку №${n} Клоду →`, fn: showToClaude } : { label: `📝 Открыть Домашку №${n} →`, fn: () => switchTask("h:" + hid) };
  }
  const next = nextLessonKey();
  if (next) return { label: `📘 Открыть Урок ${LESSON[next.slice(2)].n} →`, fn: () => switchTask(next) };
  return { label: "Вернуться в игру →", fn: closeEditor };
}

// если открыто не то задание, которое сейчас нужно, — подсказываем
function taskNote(T) {
  const s = G.save;
  if (T.kind === "homework" && s.hw[T.id] === "checked") {
    setNote("✅ Код проверен! Теперь покажи его Клоду.", "📜 Показать Клоду →", showToClaude, true);
    return;
  }
  const hid = pendingHw();
  const finished = T.kind === "sandbox" || (T.kind === "practice" && s.practice[T.id]) || (T.kind === "homework" && s.hw[T.id] === "done");
  if (!finished) return;
  const head = T.kind === "practice" ? `Урок ${T.lesson.n} уже пройден ✅ ` : T.kind === "homework" ? "Эта домашка уже сдана ⭐ " : "";
  if (hid) {
    const n = HOMEWORK[hid].lesson.n;
    if (s.hw[hid] === "checked") setNote(`${head}Домашка №${n} проверена — покажи её Клоду.`, "📜 Показать Клоду →", showToClaude);
    else setNote(`${head}Сейчас нужна Домашка №${n}.`, "📝 Открыть домашку →", () => switchTask("h:" + hid));
    return;
  }
  // домашек нет: говорим, что нужно сейчас
  const next = nextLessonKey();
  if (T.kind === "sandbox") {
    if (next) setNote(`Урок ${LESSON[next.slice(2)].n} ещё не пройден.`, "📘 Открыть урок →", () => switchTask(next));
    return;
  }
  const step = nextStep();
  setNote(`${head}Сейчас нужно: ${objective()}`, step.label, step.fn);
}

// домашка пустая, а код для неё уже написан в другом задании (например, в уроке)
async function suggestCarry(T, prev) {
  const s = G.save;
  const key = "h:" + T.id;
  const own = (s.code[key] || "").trim();
  if (s.hw[T.id] !== "given" || (own && own !== (T.starter || "").trim()) || !LuaRT.available()) return;
  for (const k of [prev, "p:" + T.lesson.id]) {
    const code = k && k !== key ? s.code[k] : "";
    if (!code || !code.trim()) continue;
    const res = await runCheck(T, code);
    if (Editor.key !== key || document.getElementById("editor").hidden) return;
    if (res.ok) {
      setNote(`Ты уже написал эту домашку в «${taskFor(k).title}» — и код подходит!`, "Перенести сюда →", () => carryToHw(T.id, code), true);
      return;
    }
  }
}

function loadTask(key) {
  const s = G.save;
  const prev = s.lastTask;
  Editor.key = key;
  s.lastTask = key;
  fillTaskSelect(key);
  const T = taskFor(key);
  renderTaskHead(T);
  document.getElementById("edCardBody").innerHTML = T.card || "";
  const code = s.code[key] ?? T.starter ?? "";
  const ta = document.getElementById("edCode");
  ta.value = code;
  Editor.errLine = null;
  refreshHl();
  clearOut();
  setResult("");
  document.getElementById("edHint").hidden = true;
  document.getElementById("edCheck").hidden = !T.check && T.kind !== "custom";
  document.getElementById("edCheck").textContent = T.kind === "custom" ? "✓ Готово" : "✓ Проверить";
  const card = document.getElementById("edCard");
  card.open = T.kind === "practice" && !G.save.practice[T.id];
  card.hidden = !T.card;
  // у особого задания там пример от Клода, а не шпаргалка урока
  card.querySelector("summary").textContent = T.kind === "custom" ? "💡 Пример от Клода" : T.kind === "sandbox" ? "📖 Шпаргалки" : "📖 Шпаргалка урока";
  orderKeys(T);
  const wantsWorld = T.lesson && T.lesson.n >= 8;
  showTab(wantsWorld ? "world" : "out");
  edClaude(T.kind === "practice" ? "Прочитай шпаргалку (📖), напиши код и нажми ▶ Запуск. Потом ✓ Проверить." : T.kind === "homework" ? "Домашка! Сделай сам, а если застрял — нажми «Спросить Клода»." : T.kind === "custom" ? "Особое задание. Когда допишешь — нажми «Готово» и покажи мне." : "Песочница. Тут можно ломать всё что угодно!");
  if (document.getElementById("edNote")) {
    edClaude(T.kind === "homework" && s.hw[T.id] === "checked" ? "Код рабочий. Неси показывать — кнопка сверху." : T.kind === "sandbox" ? "Песочница — пробуй что хочешь. А урок ждёт: кнопка сверху." : "Это задание уже сделано. Жми кнопку сверху — там то, что нужно сейчас.");
  }
  if (T.kind === "homework") setTimeout(() => suggestCarry(T, prev), 60);
}

function refreshHl() {
  const ta = document.getElementById("edCode");
  const hl = document.getElementById("edHl");
  let html = highlight(ta.value);
  if (Editor.errLine) {
    const lines = html.split("\n");
    if (lines[Editor.errLine - 1] !== undefined) lines[Editor.errLine - 1] = `<span class="errline">${lines[Editor.errLine - 1] || " "}</span>`;
    html = lines.join("\n");
  }
  hl.innerHTML = html;
  const nLines = ta.value.split("\n").length;
  document.getElementById("edGutter").textContent = Array.from({ length: nLines }, (_, i) => i + 1).join("\n");
  syncScroll();
}

function syncScroll() {
  const ta = document.getElementById("edCode");
  document.getElementById("edHl").scrollTop = ta.scrollTop;
  document.getElementById("edHl").scrollLeft = ta.scrollLeft;
  document.getElementById("edGutter").scrollTop = ta.scrollTop;
}

function codeChanged() {
  const ta = document.getElementById("edCode");
  G.save.code[Editor.key] = ta.value;
  Editor.errLine = null;
  refreshHl();
  saveSoon();
}

function insertAtCursor(text) {
  const ta = document.getElementById("edCode");
  const st = ta.selectionStart, en = ta.selectionEnd;
  const before = ta.value.slice(0, st);
  const lineStart = before.lastIndexOf("\n") + 1;
  const indent = before.slice(lineStart).match(/^\s*/)[0];
  let t = text.replace(/\n/g, "\n" + indent);
  let cur = t.indexOf("|");
  if (cur >= 0) t = t.replace("|", "");
  else cur = t.length;
  ta.value = before + t + ta.value.slice(en);
  ta.focus();
  ta.selectionStart = ta.selectionEnd = st + cur;
  codeChanged();
}

const INDENT_AFTER = /(\bthen|\bdo|\belse|\brepeat|function\s*[\w.:]*\s*\([^)]*\)|\{)\s*$/;

function newlineIndent() {
  const ta = document.getElementById("edCode");
  const v = ta.value;
  let st = ta.selectionStart;
  let en = ta.selectionEnd;
  // умный Enter: курсор стоит перед закрывающими ") или ) — переносим всю строку,
  // иначе print("|") после Enter ломает текст в кавычках
  if (st === en) {
    let eol = v.indexOf("\n", st);
    if (eol < 0) eol = v.length;
    const rest = v.slice(st, eol);
    const head = v.slice(v.lastIndexOf("\n", st - 1) + 1, st).replace(/--.*$/, "");
    if (rest && (/^["'][)\]}"']*\s*$/.test(rest) || (/^[)\]]+\s*$/.test(rest) && !INDENT_AFTER.test(head)))) st = en = eol;
  }
  const before = v.slice(0, st);
  const line = before.slice(before.lastIndexOf("\n") + 1);
  let indent = line.match(/^\s*/)[0];
  if (INDENT_AFTER.test(line.replace(/--.*$/, ""))) indent += "  ";
  const t = "\n" + indent;
  ta.value = before + t + v.slice(en);
  ta.selectionStart = ta.selectionEnd = st + t.length;
  codeChanged();
}

// сначала то, что нужно с первого урока; потом слова; потом остальные знаки
const QUICK_KEYS = [
  ["print", 'print("|")'], ["local", "local |"], ['"', '"|"'], ["(", "(|)"], [")", ")"], ["=", " = "], ["..", " .. "], ["--", "-- "],
  ["if", "if | then\n  \nend"], ["else", "else\n  "], ["for", "for i = 1, 10 do\n  |\nend"], ["while", "while | do\n  wait(0.1)\nend"],
  ["function", "local function |()\n  \nend"], ["end", "end"], ["return", "return |"], ["wait", "wait(1)"],
  ["Part", 'Instance.new("Part")'], ["Vector3", "Vector3.new(|)"], ["Color3", "Color3.fromRGB(|)"], ["workspace", "workspace"],
  ["Anchored", ".Anchored = true"], ["Connect", ":Connect(function(hit)\n  |\nend)"],
  [".", "."], [",", ", "], [":", ":"], ["==", " == "], ["~=", " ~= "], ["<", " < "], [">", " > "],
  ["+", " + "], ["-", " - "], ["*", " * "], ["/", " / "], ["{", "{|}"], ["[", "[|]"], ["#", "#"], ["_", "_"], ["⇥", "  "],
];
// какие клавиши нужны в уроке — они встают сразу после print, local, ", ( ), =, .., --
const LESSON_KEYS = {
  2: ["-", "+"],
  3: ["*", "/", "+", "-"],
  4: ["if", "else", "end", "==", "~=", ">", "<"],
  5: ["for", "while", "wait", "end", ","],
  6: ["function", "return", "end", ","],
  7: ["{", "[", "#", ",", "for", "end"],
  8: ["Part", "Vector3", "Color3", "Anchored", "workspace", ".", ","],
  9: ["Part", "Connect", "if", "end", ".", ":", "Anchored", "workspace"],
  10: ["Connect", "Part", "if", "end", ".", ":", "workspace"],
};

function buildKeys() {
  const el = document.getElementById("edKeys");
  for (const [label, ins] of QUICK_KEYS) {
    const b = document.createElement("button");
    b.type = "button";
    b.textContent = label;
    if (/^[a-zA-Z]/.test(label)) b.className = "word";
    // не отдаём фокус кнопке, чтобы клавиатура не закрывалась
    b.addEventListener("pointerdown", (e) => e.preventDefault());
    b.addEventListener("click", () => insertAtCursor(ins));
    el.appendChild(b);
    Editor.keyBtns[label] = b;
  }
}

// порядок быстрых клавиш под задание: нужные уроку — в начале ряда
function orderKeys(T) {
  const el = document.getElementById("edKeys");
  const head = QUICK_KEYS.slice(0, 8).map((k) => k[0]);
  const want = head.concat((T.lesson && LESSON_KEYS[T.lesson.n]) || [], QUICK_KEYS.map((k) => k[0]));
  const seen = new Set();
  for (const k of want) {
    if (seen.has(k) || !Editor.keyBtns[k]) continue;
    seen.add(k);
    el.appendChild(Editor.keyBtns[k]);
  }
  el.scrollLeft = 0;
}

// ---------- запуск ----------
function clearOut() {
  document.getElementById("edOut").innerHTML = '<div class="o-dim">Здесь появится вывод (Output). Нажми ▶ Запуск.</div>';
  Editor.outBuf = [];
  Editor.lastOut = [];
  Editor.lastErr = null;
  // старой ошибки больше нет — и кнопки «Почему ошибка?» тоже
  document.getElementById("edAskErr").hidden = true;
}

// вывод копим и рисуем один раз за кадр: print в цикле не вешает страницу
const OUT_MAX = 400;
function outLine(kind, text, hint) {
  const buf = Editor.outBuf;
  buf.push([kind, text, hint]);
  if (buf.length > OUT_MAX * 2) buf.splice(0, buf.length - OUT_MAX);
  Editor.lastOut.push((kind === "print" ? "" : kind + ": ") + text);
  if (Editor.lastOut.length > 60) Editor.lastOut.shift();
  if (!Editor.outRaf) Editor.outRaf = requestAnimationFrame(flushOut);
}

function flushOut() {
  Editor.outRaf = 0;
  const buf = Editor.outBuf;
  if (!buf.length) return;
  Editor.outBuf = [];
  const el = document.getElementById("edOut");
  if (el.querySelector(".o-dim")) el.innerHTML = "";
  const frag = document.createDocumentFragment();
  for (const [kind, text, hint] of buf.slice(-OUT_MAX)) {
    const d = document.createElement("div");
    d.className = "o-" + kind;
    d.textContent = (kind === "error" ? "✖ " : kind === "warn" ? "⚠ " : "") + text;
    frag.appendChild(d);
    if (hint) {
      const h = document.createElement("div");
      h.className = "o-hint";
      h.textContent = "Клод: " + hint;
      frag.appendChild(h);
    }
  }
  el.appendChild(frag);
  for (let extra = el.children.length - OUT_MAX; extra > 0; extra--) el.removeChild(el.firstChild);
  el.scrollTop = el.scrollHeight;
}

function runCode() {
  if (!LuaRT.available()) {
    outLine("error", "Движок Lua не загрузился. Нужен интернет, чтобы скачать его один раз. Обнови страницу.");
    return;
  }
  stopRun();
  clearOut();
  const el = document.getElementById("edOut");
  el.innerHTML = "";
  const code = document.getElementById("edCode").value;
  let sawPart = false;
  Editor.rt = LuaRT.create({
    playerName: G.save.name || "Player",
    onOut(kind, text, hint, line) {
      if (kind === "sound") { sfx("blip"); return; }
      outLine(kind, text, hint);
      if (kind === "error") {
        Editor.lastErr = text + (hint ? " (" + hint + ")" : "");
        if (line) { Editor.errLine = line; refreshHl(); }
        document.getElementById("edAskErr").hidden = false;
      }
    },
    onWorld(w) {
      if (Editor.vp) Editor.vp.setWorld(w);
      if (!sawPart && w.parts.some((p) => p.name !== "SpawnLocation")) {
        sawPart = true;
        // точка «новое» — только если вкладка «Мир» сейчас не открыта
        if (document.getElementById("edWorld").hidden) document.querySelector('#edTabs [data-tab="world"]').classList.add("ping");
      }
    },
  });
  document.getElementById("edAskErr").hidden = true;
  Editor.rt.start(code, document.getElementById("edInPart").checked);
  document.getElementById("edRun").classList.add("running");
  G.save.stats.runs = (G.save.stats.runs || 0) + 1;
  sfx("select");
}

function stopRun() {
  if (Editor.rt) Editor.rt.stop();
  Editor.rt = null;
  document.getElementById("edRun").classList.remove("running");
}

function showTab(tab) {
  document.getElementById("editor").classList.toggle("world", tab === "world");
  document.querySelectorAll("#edTabs [data-tab]").forEach((b) => b.classList.toggle("on", b.dataset.tab === tab));
  document.getElementById("edOut").hidden = tab !== "out";
  document.getElementById("edWorld").hidden = tab !== "world";
  if (tab === "world") {
    document.querySelector('#edTabs [data-tab="world"]').classList.remove("ping");
    if (!Editor.vp) {
      Editor.vp = Viewport.create(document.getElementById("edCanvas"), {
        playerName: () => G.save.name || "Player",
        onTapPart(p) {
          if (!Editor.rt) return toastEd("Сначала нажми ▶ Запуск");
          if (p.click && Editor.rt.click(p.id)) toastEd(`👆 Клик по «${p.name}» (ClickDetector)`);
          else { Editor.rt.touch(p.id); toastEd(`🚶 Персонаж идёт к «${p.name}»…`); }
        },
      });
    }
    clearTimeout(showTab.t);
    showTab.t = setTimeout(() => {
      // за это время редактор могли закрыть или переключить вкладку
      if (document.getElementById("editor").hidden || document.getElementById("edWorld").hidden) return;
      Editor.vp.resize();
      Editor.vp.start();
    }, 220);
  } else if (Editor.vp) Editor.vp.stop();
}

function toastEd(t) {
  const el = document.getElementById("edToast");
  el.textContent = t;
  el.classList.add("show");
  clearTimeout(toastEd.t);
  toastEd.t = setTimeout(() => el.classList.remove("show"), 1600);
}

function setResult(html, ok) {
  const el = document.getElementById("edResult");
  el.innerHTML = html;
  el.className = ok === true ? "ok" : ok === false ? "bad" : "";
  el.hidden = !html;
}

function edClaude(text) {
  document.getElementById("edClaudeText").textContent = text;
}

// автопроверка: отдельный тихий запуск с «промоткой» времени
async function runCheck(T, code) {
  const out = [], errors = [], warns = [];
  const rt = LuaRT.create({
    playerName: G.save.name || "Player",
    onOut(kind, text, hint, line) {
      if (kind === "print") out.push(text);
      else if (kind === "warn") warns.push(text);
      else if (kind === "error") errors.push({ text, hint, line });
    },
  });
  rt.startSilent(code, document.getElementById("edInPart").checked);
  rt.fastForward(T.time || 2.5);
  const sim = {
    async touchEach(pred) {
      const ids = rt.world.parts.map((p) => p.id);
      for (const id of ids) {
        if (rt.world.avatar && rt.world.avatar.dead) rt.fastForward(3.5);
        rt.touch(id);
        // смотрим часто: персонаж оживает через 3 секунды, и смерть можно пропустить
        for (let t = 0; t < 6; t += 0.25) {
          rt.fastForward(0.25);
          if (pred(rt.world)) return true;
        }
      }
      return false;
    },
    async clickEachChanged() {
      for (const p of rt.world.parts.filter((q) => q.click)) {
        const before = [p.r, p.g, p.b].join();
        rt.click(p.id);
        rt.fastForward(1.5);
        const np = rt.world.parts.find((q) => q.id === p.id);
        if (np && [np.r, np.g, np.b].join() !== before) return true;
      }
      return false;
    },
  };
  const r = { out, warns, errors, get world() { return rt.world; }, code, sim };
  let res;
  try {
    res = await T.check(r);
  } catch (e) {
    res = { ok: false, msg: "Проверка споткнулась: " + e.message };
  }
  rt.stop();
  // первая ошибка Lua: редактор подсветит строку и покажет «Почему ошибка?»
  if (res && !res.ok && errors.length) res.err = errors[0];
  return res;
}

// показать ошибку из проверки так же, как после ▶ Запуск
function showCheckErr(err) {
  document.getElementById("edAskErr").hidden = !err;
  if (!err) return;
  Editor.lastErr = err.text + (err.hint ? " (" + err.hint + ")" : "");
  if (err.line) {
    Editor.errLine = err.line;
    refreshHl();
  }
}

// закрыть шпаргалку и прокрутить верх, чтобы результат и кнопки Клода были видны
function revealResult() {
  document.getElementById("edCard").open = false;
  const top = document.querySelector(".edTop");
  if (top) top.scrollTop = 0;
}

async function checkTask() {
  const T = taskFor(Editor.key);
  const code = document.getElementById("edCode").value;
  G.save.code[Editor.key] = code;
  revealResult();
  if (T.kind === "custom") {
    if (!code.trim() || code.trim() === T.starter.trim()) {
      setResult("Сначала напиши код для задания, потом жми «Готово».", false);
      return;
    }
    if (T.custom.status !== "done") T.custom.status = "ready";
    setResult(`✓ Записал! Теперь покажи Клоду. <button id="edBack" class="pill">📜 Показать Клоду →</button>`, true);
    edClaude("Жду тебя. Посмотрим, что ты там накодил.");
    document.getElementById("edBack").onclick = showToClaude;
    renderTaskHead(T, true);
    saveSoon();
    return;
  }
  if (!LuaRT.available()) return setResult("Движок Lua не загрузился — нужен интернет.", false);
  setResult("Проверяю…");
  const s = G.save;
  const hid = pendingHw();
  // урок уже пройден, а Клод ждёт домашку — может, домашку пишут не туда
  const wrongPlace = T.kind === "practice" && s.practice[T.id] && hid && s.hw[hid] === "given";
  const res = await runCheck(T, code);
  if (!res.ok) {
    sfx("hurt");
    setResult("✖ Пока не получилось. " + escHtml(res.msg || ""), false);
    edClaude(["Почти! Читай подсказку и пробуй ещё.", "Ошибки — это нормально. Я делаю их миллион в секунду.", "Не сдавайся. Каждый программист видит красное чаще, чем зелёное."][Math.floor(Math.random() * 3)]);
    Editor.fails = (Editor.fails || 0) + 1;
    showCheckErr(res.err);
    if (T.hint && !wrongPlace) document.getElementById("edHint").hidden = false;
    if (wrongPlace) await hwHint(T, hid, code);
    else if (T.kind === "homework") await otherHwHint(T, code);
    return;
  }
  document.getElementById("edAskErr").hidden = true;
  if (T.kind === "homework" && s.hw[T.id] === "done") {
    // уже сдана: показывать Клоду нечего, говорим, что нужно сейчас
    const step = nextStep();
    setResult(`⭐ Эта домашка уже сдана — код и сейчас работает. ${escHtml(res.msg || "")}<br>Сейчас нужно: ${escHtml(objective())} <button id="edBack" class="pill">${escHtml(step.label)}</button>`, true);
    edClaude("Эту домашку я уже принял. Смотри, что нужно сейчас.");
    document.getElementById("edBack").onclick = step.fn;
    saveSoon();
    return;
  }
  sfx("victory");
  confetti();
  if (T.kind === "practice") {
    const first = !s.practice[T.id];
    s.practice[T.id] = true;
    setResult(`✓ Урок ${T.lesson.n} пройден!${first ? " +10 XP" : ""} ${escHtml(res.msg || "")} <button id="edBack" class="pill">Вернуться в игру →</button>`, true);
    edClaude("Гениально! Возвращайся в мир — там кое-что изменилось.");
    document.getElementById("edBack").onclick = closeEditor;
    if (first) onPracticeDone(T.id);
    else if (wrongPlace) await hwHint(T, hid, code);
  } else if (T.kind === "homework") {
    if (s.hw[T.id] !== "done") s.hw[T.id] = "checked";
    setResult(`✓ Домашка работает! ${escHtml(res.msg || "")}<br>Теперь покажи её Клоду. <button id="edBack" class="pill">📜 Показать Клоду →</button>`, true);
    edClaude("Код рабочий. Неси показывать — я жду.");
    document.getElementById("edBack").onclick = showToClaude;
    fillTaskSelect(Editor.key);
    renderTaskHead(T, true);
  }
  saveSoon();
}

// подсказка под результатом: домашка — это другое задание
async function hwHint(T, hid, code) {
  const n = HOMEWORK[hid].lesson.n;
  const fits = (await runCheck(taskFor("h:" + hid), code)).ok;
  if (Editor.key !== "p:" + T.id) return;
  const d = document.createElement("div");
  d.style.cssText = "margin-top:6px;color:var(--gold)";
  d.textContent = fits
    ? `💡 Это код для Домашки №${n}, а открыт Урок ${T.lesson.n} (он уже пройден). Для домашки код подходит! `
    : `💡 Урок ${T.lesson.n} уже пройден. Домашка №${n} — это другое задание, оно открывается отдельно. `;
  const b = document.createElement("button");
  b.type = "button";
  b.className = "pill";
  b.textContent = fits ? "Перенести в домашку →" : "📝 Открыть домашку →";
  b.onclick = fits ? () => carryToHw(hid, code) : () => switchTask("h:" + hid);
  d.appendChild(b);
  document.getElementById("edResult").appendChild(d);
  edClaude(`Стоп! Ты в Уроке ${T.lesson.n}, а нужна Домашка №${n}. Жми кнопку выше.`);
}

// домашка не прошла — а может, это код для другой заданной домашки?
async function otherHwHint(T, code) {
  const s = G.save;
  const key = Editor.key;
  for (const L of LESSONS) {
    const H = HOMEWORK[L.homework.id];
    // свою мини-игру (№10) проверяет сам Клод, её не угадываем
    if (H.id === T.id || H.review || s.hw[H.id] !== "given") continue;
    const res = await runCheck(taskFor("h:" + H.id), code);
    if (Editor.key !== key || document.getElementById("editor").hidden) return;
    if (!res.ok) continue;
    const n = L.n;
    const d = document.createElement("div");
    d.style.cssText = "margin-top:6px;color:var(--gold)";
    d.textContent = `💡 Это код для Домашки №${n}, а открыта Домашка №${T.lesson.n}. `;
    const b = document.createElement("button");
    b.type = "button";
    b.className = "pill";
    b.textContent = "Перенести →";
    b.onclick = () => carryToHw(H.id, code, key);
    d.appendChild(b);
    document.getElementById("edResult").appendChild(d);
    document.getElementById("edHint").hidden = true;
    edClaude(`Это же Домашка №${n}! Жми «Перенести» — и код окажется на своём месте.`);
    return;
  }
}

function askClaudeAboutCode(withErr) {
  // ошибки уже нет (сменили задание или всё прошло) — просто просим помочь
  if (withErr && !Editor.lastErr) withErr = false;
  const T = taskFor(Editor.key);
  const code = document.getElementById("edCode").value;
  const msg = withErr
    ? `Почему у меня ошибка?\n\nОшибка: ${Editor.lastErr}`
    : `Помоги с заданием «${T.title}». Я не понимаю, что делать дальше.`;
  openChat(msg, { code, task: T.task, out: Editor.lastOut.slice(-12).join("\n") });
}

function confetti() {
  const box = document.getElementById("edResult");
  for (let i = 0; i < 18; i++) {
    const s = document.createElement("i");
    s.className = "conf";
    s.style.left = Math.random() * 100 + "%";
    s.style.background = ["#ffe03a", "#5aff8a", "#ff5aa0", "#5ac8ff", "#da7756"][i % 5];
    s.style.animationDelay = Math.random() * 0.3 + "s";
    box.appendChild(s);
    setTimeout(() => s.remove(), 1400);
  }
}

function fitSheet() {
  const vv = window.visualViewport;
  const h = vv ? vv.height : window.innerHeight;
  document.querySelectorAll(".sheet").forEach((el) => (el.style.height = h + "px"));
  // открыта клавиатура телефона — прячем всё лишнее, чтобы было видно код
  const ed = document.getElementById("editor");
  const focused = document.activeElement && document.activeElement.id === "edCode";
  ed.classList.toggle("kb", focused && h < 520);
}

function setupEditor() {
  buildKeys();
  const ta = document.getElementById("edCode");
  ta.addEventListener("input", codeChanged);
  ta.addEventListener("scroll", syncScroll);
  ta.addEventListener("keydown", (e) => {
    if (e.key === "Tab") { e.preventDefault(); insertAtCursor("  "); }
    else if (e.key === "Enter" && !e.isComposing) { e.preventDefault(); newlineIndent(); }
  });
  ta.addEventListener("beforeinput", (e) => {
    if (e.inputType === "insertLineBreak" || e.inputType === "insertParagraph") { e.preventDefault(); newlineIndent(); }
  });
  document.getElementById("edTask").addEventListener("change", (e) => { stopRun(); loadTask(e.target.value); });
  document.getElementById("edClose").onclick = closeEditor;
  document.getElementById("edRun").onclick = runCode;
  document.getElementById("edStop").onclick = () => { stopRun(); outLine("warn", "Скрипт остановлен."); };
  document.getElementById("edCheck").onclick = checkTask;
  document.getElementById("edAsk").onclick = () => askClaudeAboutCode(false);
  document.getElementById("edAskErr").onclick = () => askClaudeAboutCode(true);
  document.getElementById("edHint").onclick = () => {
    const T = taskFor(Editor.key);
    outLine("hint", "Подсказка:\n" + (T.hint || "Перечитай шпаргалку 📖"));
    showTab("out");
    revealResult();
  };
  document.getElementById("edReset").onclick = () => {
    const T = taskFor(Editor.key);
    if (document.getElementById("edReset").dataset.armed !== "1") {
      document.getElementById("edReset").dataset.armed = "1";
      document.getElementById("edReset").textContent = "Точно стереть?";
      setTimeout(() => { document.getElementById("edReset").dataset.armed = ""; document.getElementById("edReset").textContent = "⟲ Сброс"; }, 2500);
      return;
    }
    document.getElementById("edReset").dataset.armed = "";
    document.getElementById("edReset").textContent = "⟲ Сброс";
    ta.value = T.starter || "";
    codeChanged();
  };
  document.querySelectorAll("#edTabs [data-tab]").forEach((b) => (b.onclick = () => showTab(b.dataset.tab)));
  document.getElementById("vpIn").onclick = () => Editor.vp && Editor.vp.zoomIn();
  document.getElementById("vpOut").onclick = () => Editor.vp && Editor.vp.zoomOut();
  document.getElementById("vpReset").onclick = () => Editor.vp && Editor.vp.reset();
  // мир виден, только если открыт редактор и вкладка «Мир»
  const worldShown = () => Editor.vp && !document.getElementById("editor").hidden && !document.getElementById("edWorld").hidden;
  window.addEventListener("resize", () => { fitSheet(); if (worldShown()) Editor.vp.resize(); });
  if (window.visualViewport) window.visualViewport.addEventListener("resize", fitSheet);
  // окно «Мир» меняет размер, когда открывается шпаргалка или результат — перерисовываем canvas
  if (window.ResizeObserver) new ResizeObserver(() => { if (worldShown()) Editor.vp.resize(); }).observe(document.getElementById("edPane"));
  ta.addEventListener("focus", () => setTimeout(fitSheet, 300));
  ta.addEventListener("blur", () => setTimeout(fitSheet, 100));
  drawClaude(document.getElementById("edClaudeAva").getContext("2d"), 0, 0, "down", 0.3);
}
