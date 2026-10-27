// Запуск Luau-кода игрока через Fengari (Lua 5.3 в браузере) + мини-Roblox из prelude.lua
const LuaRT = (() => {
  const TOO_LONG = "__TOO_LONG__";

  function available() {
    return typeof window !== "undefined" && !!window.fengari;
  }

  // Luau → Lua 5.3: то, что пишут в Roblox, но чего нет в обычном Lua
  function preprocess(src) {
    src = String(src)
      .replace(/[“”„«»″]/g, '"')
      .replace(/[‘’‚′]/g, "'")
      .replace(/—/g, "--")
      .replace(/–/g, "-")
      .replace(/[   ]/g, " ")
      .replace(/\r\n?/g, "\n");
    // `текст {выражение}` — интерполяция строк Luau
    src = src.replace(/`([^`\n]*)`/g, (_, body) => {
      const parts = [];
      let rest = body;
      const re = /\{([^}]*)\}/;
      let m;
      while ((m = re.exec(rest))) {
        if (m.index > 0) parts.push(JSON.stringify(rest.slice(0, m.index)));
        parts.push("tostring(" + m[1] + ")");
        rest = rest.slice(m.index + m[0].length);
      }
      if (rest.length || !parts.length) parts.push(JSON.stringify(rest));
      return "(" + parts.join(" .. ") + ")";
    });
    src = rewriteCompound(src);
    // local x: number = 5  →  local x = 5
    return src.replace(/^(\s*local\s+[A-Za-z_]\w*)\s*:\s*[A-Za-z_][\w.<>?]*\s*=/gm, "$1 =");
  }

  // x += 1  →  x = x + (1), в любом месте строки (строки и комментарии пропускаем)
  function rewriteCompound(s) {
    const isName = (c) => /[A-Za-z0-9_]/.test(c || "");
    const isStart = (c) => /[A-Za-z_]/.test(c || "");
    function skipString(i) {
      const q = s[i];
      if (q === "[") {
        const m = s.slice(i).match(/^\[(=*)\[/);
        if (m) {
          const close = "]" + m[1] + "]";
          const j = s.indexOf(close, i + m[0].length);
          return j < 0 ? s.length : j + close.length;
        }
        return i + 1;
      }
      let j = i + 1;
      while (j < s.length && s[j] !== q && s[j] !== "\n") j += s[j] === "\\" ? 2 : 1;
      return j + 1;
    }
    function skipBalanced(i) {
      const open = s[i];
      const close = open === "(" ? ")" : open === "[" ? "]" : "}";
      let depth = 0;
      let j = i;
      while (j < s.length) {
        const c = s[j];
        if (c === '"' || c === "'") { j = skipString(j); continue; }
        if (c === open) depth++;
        else if (c === close) { depth--; if (depth === 0) return j + 1; }
        j++;
      }
      return s.length;
    }
    function ws(i) { while (i < s.length && (s[i] === " " || s[i] === "\t")) i++; return i; }
    const KW = /^(end|else|elseif|then|do|until|local|return|break|if|for|while|repeat|function|in)$/;
    function exprEnd(i) {
      for (let guard = 0; guard < 200; guard++) {
        i = ws(i);
        // унарные
        while (true) {
          if (s[i] === "-" && s[i + 1] !== "-") { i = ws(i + 1); continue; }
          if (s[i] === "#") { i = ws(i + 1); continue; }
          if (s.startsWith("not", i) && !isName(s[i + 3])) { i = ws(i + 3); continue; }
          break;
        }
        const c = s[i];
        let m;
        if ((m = s.slice(i).match(/^(0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+)/))) i += m[0].length;
        else if (c === '"' || c === "'" || (c === "[" && /^\[=*\[/.test(s.slice(i)))) i = skipString(i);
        else if (c === "(" || c === "{") i = skipBalanced(i);
        else if (isStart(c)) {
          m = s.slice(i).match(/^[A-Za-z_]\w*/);
          if (KW.test(m[0])) return i;
          i += m[0].length;
        } else return i;
        // суффиксы: .a  :b(...)  [..]  (...)  "str"
        while (true) {
          const j = ws(i);
          if (s[j] === "." && s[j + 1] !== "." && isStart(s[ws(j + 1)])) { i = ws(j + 1); i += s.slice(i).match(/^[A-Za-z_]\w*/)[0].length; continue; }
          if (s[j] === ":" && isStart(s[ws(j + 1)])) { i = ws(j + 1); i += s.slice(i).match(/^[A-Za-z_]\w*/)[0].length; continue; }
          if (s[j] === "[" && !/^\[=*\[/.test(s.slice(j))) { i = skipBalanced(j); continue; }
          if (s[j] === "(") { i = skipBalanced(j); continue; }
          break;
        }
        const j = ws(i);
        const op = s.slice(j).match(/^(\.\.(?!\.)|==|~=|<=|>=|\/\/|[<>+\-*\/%^]|and(?![\w])|or(?![\w]))/);
        if (!op || (op[0] === "-" && s[j + 1] === "-")) return i;
        i = j + op[0].length;
      }
      return i;
    }
    let out = "";
    let i = 0;
    while (i < s.length) {
      const c = s[i];
      if (c === "-" && s[i + 1] === "-") {
        const m = s.slice(i).match(/^--\[(=*)\[/);
        let j;
        if (m) { const close = "]" + m[1] + "]"; j = s.indexOf(close, i); j = j < 0 ? s.length : j + close.length; }
        else { j = s.indexOf("\n", i); if (j < 0) j = s.length; }
        out += s.slice(i, j); i = j; continue;
      }
      if (c === '"' || c === "'" || (c === "[" && /^\[=*\[/.test(s.slice(i)))) {
        const j = skipString(i); out += s.slice(i, j); i = j; continue;
      }
      if (isStart(c) && !isName(s[i - 1]) && s[i - 1] !== ".") {
        const m = s.slice(i).match(/^[A-Za-z_]\w*(?:\s*\.\s*[A-Za-z_]\w*|\[[^\]\n]+\])*/);
        const lhs = m[0];
        const k = ws(i + lhs.length);
        const op = s.slice(k).match(/^(\.\.|\/\/|[+\-*\/%^])=(?!=)/);
        if (op && !KW.test(lhs)) {
          const rs = ws(k + op[0].length);
          const re = exprEnd(rs);
          const rhs = s.slice(rs, re).trim();
          if (rhs) {
            out += `${lhs} = ${lhs} ${op[1]} (${rhs})`;
            i = re;
            continue;
          }
        }
        out += lhs;
        i += lhs.length;
        continue;
      }
      out += c;
      i++;
    }
    return out;
  }

  // Ошибки Lua → понятные подсказки на русском
  function explain(msg) {
    msg = String(msg || "ошибка");
    if (msg.indexOf(TOO_LONG) >= 0) {
      return {
        text: "Скрипт слишком долго работал без паузы, и я его остановил.",
        hint: "Если у тебя бесконечный цикл (while true do), добавь внутрь wait(0.1). В Roblox без wait() такой цикл заморозит игру.",
      };
    }
    let line = null;
    const lm = msg.match(/^Script:(\d+):\s*/);
    if (lm) {
      line = +lm[1];
      msg = msg.slice(lm[0].length);
    }
    const hints = [
      [/attempt to call a nil value \((?:global|field|method) '([^']+)'\)/, (m) => `Команды «${m[1]}» не существует. Проверь опечатку: Luau различает большие и маленькие буквы (print, а не Print).`],
      [/attempt to call a (\w+) value/, (m) => `Ты пытаешься вызвать как функцию то, что ею не является (это ${m[1]}).`],
      [/attempt to perform arithmetic on a nil value(?: \((?:global|local|field) '([^']+)'\))?/, (m) => `${m[1] ? "«" + m[1] + "»" : "Значение"} пустое (nil). Может, переменная не создана или в имени опечатка?`],
      [/attempt to perform arithmetic on a string value/, () => "Текст нельзя складывать плюсом. Чтобы склеить текст, используй две точки: \"HP: \" .. hp"],
      [/attempt to concatenate a nil value(?: \((?:global|local|field) '([^']+)'\))?/, (m) => `Склеиваешь (..) текст с пустым значением${m[1] ? " «" + m[1] + "»" : ""}. Такой переменной нет или в ней nil.`],
      [/attempt to concatenate a (boolean|table) value/, (m) => `Нельзя склеить текст с ${m[1] === "boolean" ? "true/false" : "таблицей"}. Оберни в tostring(...)`],
      [/attempt to index a nil value(?: \((?:global|local|field|upvalue) '([^']+)'\))?/, (m) => `Ты пишешь «${m[1] || "что-то"}.что-то», но ${m[1] ? "«" + m[1] + "»" : "это"} пустое (nil). Объект не создан или имя неверное.`],
      [/attempt to compare/, () => "Сравнивать можно числа с числами и текст с текстом. Проверь, что с обеих сторон одинаковые типы."],
      [/'end' expected/, () => "Не хватает слова end. Каждый if, for, while и function нужно закрыть словом end."],
      [/'then' expected/, () => "После условия в if нужно слово then: if hp > 0 then"],
      [/'do' expected/, () => "После for или while нужно слово do: for i = 1, 10 do"],
      [/'=' expected near/, () => "Компьютер ждал знак «=». Проверь слово перед этим местом: может, опечатка или лишний пробел в имени?"],
      [/'\)' expected/, () => "Не хватает закрывающей скобки «)»."],
      [/'}' expected/, () => "Не хватает закрывающей фигурной скобки «}»."],
      [/unfinished string/, () => "Строка не закрыта: не хватает кавычки \" в конце текста."],
      [/unexpected symbol near '!'/, () => "В Luau «не равно» пишется ~= (а не !=), а «не» — словом not."],
      [/near '?<\\\d+>/, () => "Русские буквы можно писать только внутри кавычек: print(\"Привет\"). Имена переменных и команд — латиницей."],
      [/unexpected symbol near '([^']*)'/, (m) => `Непонятный символ «${m[1]}». Проверь кавычки, скобки и знаки.`],
      [/<eof> expected near 'end'/, () => "Лишнее слово end. Посчитай: сколько if/for/function открыто, столько end и нужно."],
      [/malformed number/, () => "Странное число. Дробные числа пишутся через точку: 0.5, а не 0,5"],
      [/bad argument #(\d+) to '([^']+)'/, (m) => `Функции ${m[2]} передано что-то не то (аргумент №${m[1]}).`],
      [/stack overflow/, () => "Функция вызывает сама себя бесконечно."],
    ];
    let hint = "";
    for (const [re, fn] of hints) {
      const m = msg.match(re);
      if (m) {
        hint = fn(m);
        break;
      }
    }
    msg = msg.replace(/'?(<\\\d+>)+'?/g, "«русская буква»");
    return { text: (line ? `Строка ${line}: ` : "") + msg, hint, line };
  }

  function create(opts) {
    const F = window.fengari;
    const { lua, lauxlib, lualib, to_luastring } = F;
    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);
    let stopped = false;

    const out = (kind, text) => {
      if (stopped) return;
      if (kind === "error") {
        const e = explain(text);
        opts.onOut("error", e.text, e.hint, e.line);
      } else opts.onOut(kind, text);
    };

    lua.lua_pushcfunction(L, (L) => {
      out(lua.lua_tojsstring(L, 1), lua.lua_tojsstring(L, 2));
      return 0;
    });
    lua.lua_setglobal(L, to_luastring("__out"));
    // виртуальное время: обычно идёт как настоящее, а для автопроверок его можно «промотать»
    let vnow = 0;
    let lastReal = performance.now();
    lua.lua_pushcfunction(L, (L) => {
      lua.lua_pushnumber(L, vnow);
      return 1;
    });
    lua.lua_setglobal(L, to_luastring("__clock"));
    lua.lua_pushstring(L, to_luastring(opts.playerName || "Player"));
    lua.lua_setglobal(L, to_luastring("__playerName"));

    function runChunk(src, name) {
      const st = lauxlib.luaL_loadbufferx(L, to_luastring(src), null, to_luastring(name), null);
      if (st !== lua.LUA_OK) {
        const e = lua.lua_tojsstring(L, -1);
        lua.lua_pop(L, 1);
        throw new Error(e);
      }
      if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
        const e = lua.lua_tojsstring(L, -1);
        lua.lua_pop(L, 1);
        throw new Error(e);
      }
    }
    runChunk(LUA_PRELUDE, "=prelude");

    // вызвать глобальную Lua-функцию; аргументы — числа/строки/булевы
    function call(name, args, nret) {
      if (stopped) return [];
      const top = lua.lua_gettop(L);
      lua.lua_getglobal(L, to_luastring(name));
      for (const a of args) {
        if (typeof a === "number") lua.lua_pushnumber(L, a);
        else if (typeof a === "boolean") lua.lua_pushboolean(L, a);
        else lua.lua_pushstring(L, to_luastring(String(a)));
      }
      const res = [];
      if (lua.lua_pcall(L, args.length, nret, 0) !== lua.LUA_OK) {
        out("error", lua.lua_tojsstring(L, -1));
        lua.lua_settop(L, top);
        return res;
      }
      for (let i = nret; i >= 1; i--) {
        const t = lua.lua_type(L, -i);
        if (t === lua.LUA_TNUMBER) res.push(lua.lua_tonumber(L, -i));
        else if (t === lua.LUA_TBOOLEAN) res.push(lua.lua_toboolean(L, -i));
        else if (t === lua.LUA_TSTRING) res.push(lua.lua_tojsstring(L, -i));
        else res.push(null);
      }
      lua.lua_settop(L, top);
      return res;
    }

    let world = { parts: [], avatar: null, stats: [], clock: 14, gravity: 196.2 };
    function parseSnapshot(s) {
      const parts = [];
      const stats = [];
      let avatar = null;
      let clock = 14;
      let gravity = 196.2;
      for (const line of s.split("\n")) {
        const f = line.split("\t");
        if (f[0] === "P") {
          parts.push({
            id: +f[1], name: f[2], x: +f[3], y: +f[4], z: +f[5], sx: +f[6], sy: +f[7], sz: +f[8],
            r: +f[9], g: +f[10], b: +f[11], t: +f[12], material: f[13], shape: f[14],
            click: f[15] === "1", light: f[16] === "1", anchored: f[17] === "1",
          });
        } else if (f[0] === "A") {
          avatar = { joined: f[1] === "1", dead: f[2] === "1", x: +f[3], y: +f[4], z: +f[5], hp: +f[6], maxHp: +f[7], walking: f[8] === "1" };
        } else if (f[0] === "L") {
          stats.push({ name: f[1], value: f[2] });
        } else if (f[0] === "W") {
          clock = +f[1];
          gravity = +f[2];
        }
      }
      return { parts, avatar, stats, clock, gravity };
    }

    let timer = null;
    let idleTicks = 0;
    function tick() {
      if (stopped) return;
      const r = performance.now();
      vnow += Math.min(0.1, (r - lastReal) / 1000);
      lastReal = r;
      const [count, dirty] = call("__tick", [vnow], 2);
      if (dirty) {
        const [snap] = call("__snapshot", [], 1);
        if (snap) world = parseSnapshot(snap);
        opts.onWorld && opts.onWorld(world);
      }
      if (!count) idleTicks++;
      else idleTicks = 0;
      opts.onTick && opts.onTick(count || 0);
    }

    const api = {
      get world() { return world; },
      start(code, inPart) {
        const src = preprocess(code);
        const [ok] = call("__start", [src, !!inPart], 1);
        tick();
        timer = setInterval(tick, 33);
        return !!ok;
      },
      touch(id) { call("__touch", [id], 0); },
      click(id) { const [r] = call("__click", [id], 1); return !!r; },
      hasClick(id) { const [r] = call("__hasClick", [id], 1); return !!r; },
      chat(msg) { call("__chat", [msg], 0); },
      // для автопроверок: прогнать N тиков симуляции синхронно
      fastForward(seconds) {
        const steps = Math.ceil(seconds / 0.033);
        for (let i = 0; i < steps && !stopped; i++) {
          vnow += 0.033;
          const [, dirty] = call("__tick", [vnow], 2);
          if (dirty) {
            const [snap] = call("__snapshot", [], 1);
            if (snap) world = parseSnapshot(snap);
          }
        }
        lastReal = performance.now();
      },
      // запустить без таймера (для автопроверки)
      startSilent(code, inPart) {
        const src = preprocess(code);
        const [ok] = call("__start", [src, !!inPart], 1);
        return !!ok;
      },
      stop() {
        stopped = true;
        if (timer) clearInterval(timer);
        timer = null;
      },
      get running() { return !stopped; },
      get idle() { return idleTicks > 3; },
    };
    return api;
  }

  return { available, create, preprocess, explain };
})();
