// Уроки Luau для Roblox: от print до leaderstats
// check(r) получает {out:[строки print], warns, errors:[...], world, code, sim}
// sim: touchAll(), clickAll(), ff(секунды)
const prints = (r) => r.out;
const hasLine = (r, re) => r.out.some((l) => re.test(l));
const noErr = (r) => (r.errors.length ? r.errors[0].text + (r.errors[0].hint ? "\n" + r.errors[0].hint : "") : null);
const userParts = (r) => r.world.parts.filter((p) => p.name !== "SpawnLocation" && p.name !== "Деталь");
const codeHas = (r, re) => re.test(r.code.replace(/--[^\n]*/g, ""));

const LESSONS = [
  {
    id: "l1",
    n: 1,
    title: "Первая команда",
    topic: "print",
    zone: "lab",
    card: `
<p>Игры в Roblox делают в программе <b>Roblox Studio</b>. Чтобы в игре что-то происходило (двери открывались, монеты собирались), туда пишут <b>скрипты</b> — текст на языке <b>Luau</b>.</p>
<p>Компьютер читает скрипт <b>сверху вниз</b>, строчку за строчкой, и выполняет каждую команду.</p>
<p>Первая команда — <code>print</code>. Она пишет текст в окно <b>Output</b> (Вывод). Так игра «разговаривает» с тобой.</p>
<pre>print("Привет, мир!")</pre>
<ul>
<li><code>print</code> — имя команды, пишется маленькими буквами</li>
<li><code>( )</code> — в скобках то, что мы даём команде</li>
<li><code>" "</code> — кавычки значат «это текст», а не команда</li>
</ul>
<p>Строчки, которые начинаются с <code>--</code>, — <b>комментарии</b>. Компьютер их пропускает, они для людей.</p>
<pre>-- это комментарий, его никто не выполнит
print("А это выполнится")</pre>`,
    talk: [
      "Смотри. Мой портал работает на коде. Код — это просто список команд для компьютера.",
      "Компьютер очень послушный, но очень буквальный. Ошибёшься в одной букве — и он не поймёт.",
      "Самая первая команда любого программиста — print. Она выводит текст.",
      "Напиши в редакторе: print(\"Портал, откройся!\") и нажми ▶ Запуск. Кавычки не забудь!",
    ],
    practice: {
      task: "Напиши команду print, которая выведет: Портал, откройся!",
      starter: '-- Напиши свою команду под этой строчкой\n',
      hint: 'Вот так: print("Портал, откройся!")',
      check(r) {
        const e = noErr(r);
        if (e) return { ok: false, msg: e };
        if (!r.out.length) return { ok: false, msg: "Ничего не вывелось. Нужна команда print(...)." };
        if (!hasLine(r, /портал/i)) return { ok: false, msg: "Вывелось что-то, но без слова «Портал». Текст внутри кавычек: Портал, откройся!" };
        return { ok: true };
      },
    },
    homework: {
      id: "h1",
      title: "Визитка стажёра",
      task: "Выведи 3 строчки: своё имя, сколько тебе лет и свою любимую игру. Каждую — отдельным print.",
      starter: "-- Домашка №1: три print подряд\n",
      hint: 'Три строчки, например:\nprint("Меня зовут Артём")\nprint("Мне 11 лет")\nprint("Люблю Roblox")',
      check(r) {
        const e = noErr(r);
        if (e) return { ok: false, msg: e };
        // считаем строчки с текстом: print("а\nб") — тоже две строчки, а пустые не в счёт
        const lines = r.out.flatMap((l) => String(l).split("\n")).map((l) => l.trim()).filter(Boolean);
        if (lines.length < 3 && r.out.length > lines.length) return { ok: false, msg: "Есть пустые строчки. Внутри кавычек напиши своё имя, возраст и любимую игру." };
        if (lines.length < 3) return { ok: false, msg: `Строчек вывелось: ${lines.length}. Нужно хотя бы 3.` };
        if (new Set(lines).size < 3) return { ok: false, msg: "Строчки повторяются. Нужно три разные: имя, возраст и любимая игра." };
        return { ok: true };
      },
    },
    quiz: [
      { q: "Какая команда выводит текст в Output?", a: ['print("Привет")', "say Привет", 'Print("Привет")'], ok: 0, why: "Команда print пишется маленькими буквами, а текст — в кавычках." },
      { q: "Как компьютер читает скрипт?", a: ["Сверху вниз, по строчке", "Снизу вверх", "Как захочет"], ok: 0, why: "Скрипт выполняется сверху вниз, строчка за строчкой." },
      { q: "Что делает строчка -- привет ?", a: ["Ничего, это комментарий", "Выводит «привет»", "Ломает игру"], ok: 0, why: "Две чёрточки -- начинают комментарий. Компьютер его пропускает." },
      { q: "Где ошибка: print(Привет)?", a: ["Нет кавычек вокруг текста", "Нужны квадратные скобки", "Ошибки нет"], ok: 0, why: "Текст всегда в кавычках: print(\"Привет\")." },
    ],
  },
  {
    id: "l2",
    n: 2,
    title: "Переменные",
    topic: "local, =, ..",
    zone: "slime",
    card: `
<p><b>Переменная</b> — это коробка с наклейкой. В неё кладут значение, чтобы потом достать по имени.</p>
<pre>local name = "Стажёр"
local coins = 10
print(name)
print(coins)</pre>
<ul>
<li><code>local</code> — «создаю новую коробку»</li>
<li><code>name</code> — имя коробки (латиницей, без пробелов)</li>
<li><code>=</code> — «положить внутрь»</li>
</ul>
<p>Значение можно менять:</p>
<pre>coins = coins + 5   -- было 10, стало 15
coins += 5          -- то же самое, коротко</pre>
<p>Склеить текст и переменную можно двумя точками <code>..</code></p>
<pre>print("Монет: " .. coins)</pre>
<p>Что можно класть в коробку: текст <code>"привет"</code>, числа <code>42</code>, <code>true</code>/<code>false</code> (да/нет) и <code>nil</code> — «пусто».</p>`,
    talk: [
      "Глюк стёр у слизней имена. Теперь они не помнят, кто есть кто. Кошмар, а не планета.",
      "В коде имена хранят в переменных. Переменная — это коробка с наклейкой.",
      "local hp = 100 значит: «создай коробку hp и положи туда 100».",
      "А чтобы склеить текст с переменной, ставь две точки: \"HP: \" .. hp",
    ],
    practice: {
      task: "Создай переменную hp со значением 100. Потом отними от неё 25 и выведи hp. Должно получиться 75.",
      starter: "local hp = 100\n-- отними 25 и выведи hp\n",
      hint: "hp = hp - 25\nprint(hp)",
      check(r) {
        const e = noErr(r);
        if (e) return { ok: false, msg: e };
        if (!codeHas(r, /\blocal\b/)) return { ok: false, msg: "Создай переменную через local." };
        if (!hasLine(r, /(^|\D)75(\D|$)/)) return { ok: false, msg: "В выводе нет числа 75. Отними 25 от hp и выведи hp через print." };
        // 75 должен посчитать компьютер, а не мы: hp = hp - 25 или hp -= 25
        if (!codeHas(r, /-=|[\w)\]]\s*-\s*[\w(]/)) return { ok: false, msg: "Пусть вычтет компьютер: напиши hp = hp - 25" };
        return { ok: true };
      },
    },
    homework: {
      id: "h2",
      title: "Карточка героя",
      task: "Создай две переменные: heroName (имя героя) и power (его сила, число). Выведи одной строчкой: Герой ___ имеет силу ___ — склей через ..",
      starter: "-- Домашка №2\nlocal heroName = \nlocal power = \n",
      hint: 'local heroName = "Слизень Боб"\nlocal power = 9000\nprint("Герой " .. heroName .. " имеет силу " .. power)',
      check(r) {
        const e = noErr(r);
        if (e) return { ok: false, msg: e };
        if ((r.code.match(/\blocal\b/g) || []).length < 2) return { ok: false, msg: "Нужно две переменные через local: heroName и power." };
        if (!codeHas(r, /\.\./)) return { ok: false, msg: "Склей текст и переменные двумя точками .." };
        if (!hasLine(r, /герой/i)) return { ok: false, msg: "Выведи фразу со словом «Герой»." };
        return { ok: true };
      },
    },
    quiz: [
      { q: "Как создать переменную?", a: ["local hp = 100", "hp local 100", "create hp 100"], ok: 0, why: "Сначала local, потом имя, потом = и значение." },
      { q: "local a = 5\na = a + 1\nЧему равно a?", a: ["6", "5", "a1"], ok: 0, why: "Берём старое значение 5 и прибавляем 1." },
      { q: "Чем склеивают текст в Luau?", a: ["Двумя точками ..", "Плюсом +", "Запятой ,"], ok: 0, why: "\"Монет: \" .. coins — две точки склеивают." },
      { q: "Что такое nil?", a: ["Пусто, ничего", "Ноль", "Ошибка"], ok: 0, why: "nil — значит «ничего нет». В пустой коробке лежит nil." },
    ],
  },
  {
    id: "l3",
    n: 3,
    title: "Числа и случайность",
    topic: "+ - * / math.random",
    zone: "slime",
    card: `
<p>Luau умеет считать: <code>+</code> <code>-</code> <code>*</code> (умножить) <code>/</code> (разделить), а ещё <code>%</code> (остаток) и <code>^</code> (степень).</p>
<pre>print(2 + 3 * 4)    -- 14: сначала умножение
print((2 + 3) * 4)  -- 20: скобки первыми
print(10 / 4)       -- 2.5
print(10 % 3)       -- 1, это остаток от деления</pre>
<p><code>math.random(1, 6)</code> — случайное целое число от 1 до 6, как бросок кубика:</p>
<pre>local roll = math.random(1, 6)
print("Выпало: " .. roll)</pre>
<p>Полезное: <code>math.floor(2.7)</code> → 2 (отбросить дробь), <code>math.max(3, 9)</code> → 9, <code>math.min(3, 9)</code> → 3.</p>
<p>Дробные числа пишутся через <b>точку</b>: <code>0.5</code>, а не 0,5.</p>`,
    talk: [
      "Слизни ещё и считать разучились. Один уверен, что 2 + 2 = слизь.",
      "Компьютер — это гигантский калькулятор. + - * / работают как в школе.",
      "Сначала умножение и деление, потом сложение. Скобки — самые главные.",
      "А math.random(1, 6) — это кубик. Каждый раз новое число. В играх на этом держится весь лут!",
    ],
    practice: {
      task: "Посчитай кодом, сколько секунд в одном часе (60 минут по 60 секунд), и выведи ответ.",
      starter: "-- посчитай 60 * 60\n",
      hint: "print(60 * 60)",
      check(r) {
        const e = noErr(r);
        if (e) return { ok: false, msg: e };
        if (!hasLine(r, /3600/)) return { ok: false, msg: "Ответ должен быть 3600. Используй * для умножения." };
        if (!codeHas(r, /\*|\^/)) return { ok: false, msg: "Пусть посчитает компьютер: используй умножение *." };
        return { ok: true };
      },
    },
    homework: {
      id: "h3",
      title: "Кубик удачи",
      task: "Брось кубик: создай переменную со случайным числом от 1 до 6 и выведи: Выпало: N. Запусти несколько раз — число должно меняться!",
      starter: "-- Домашка №3\n",
      hint: 'local roll = math.random(1, 6)\nprint("Выпало: " .. roll)',
      check(r) {
        const e = noErr(r);
        if (e) return { ok: false, msg: e };
        if (!codeHas(r, /math\.random\s*\(/)) return { ok: false, msg: "Нужен math.random(1, 6)." };
        if (!hasLine(r, /[1-6]/)) return { ok: false, msg: "Выведи выпавшее число." };
        return { ok: true };
      },
    },
    quiz: [
      { q: "Что выведет print(2 + 3 * 4)?", a: ["14", "20", "234"], ok: 0, why: "Сначала умножение: 3*4=12, потом +2 = 14." },
      { q: "Что делает math.random(1, 6)?", a: ["Случайное число от 1 до 6", "Всегда 6", "Сортирует числа"], ok: 0, why: "Это как бросить кубик." },
      { q: "Как правильно записать половину?", a: ["0.5", "0,5", "1/2 = 0,5"], ok: 0, why: "В коде дроби пишутся через точку." },
      { q: "Что выведет print(10 % 3)?", a: ["1", "3", "3.33"], ok: 0, why: "% — остаток: 10 = 3*3 + 1." },
    ],
  },
  {
    id: "l4",
    n: 4,
    title: "Условия: если… то…",
    topic: "if then else",
    zone: "forest",
    card: `
<p><code>if</code> — это «если». Код внутри выполнится, только если условие верно.</p>
<pre>local hp = 0
if hp <= 0 then
  print("Game Over")
else
  print("Живой!")
end</pre>
<p>Сравнения: <code>==</code> равно (два знака!), <code>~=</code> не равно, <code>&lt;</code> <code>&gt;</code> <code>&lt;=</code> <code>&gt;=</code>.</p>
<p>Можно соединять: <code>and</code> (и), <code>or</code> (или), <code>not</code> (не).</p>
<p><code>elseif</code> — ещё одна проверка:</p>
<pre>if coins >= 100 then
  print("Меч!")
elseif coins >= 50 then
  print("Щит")
else
  print("Копи дальше")
end</pre>
<p>Важно: один знак <code>=</code> кладёт значение в коробку, а два <code>==</code> сравнивают.</p>`,
    talk: [
      "Лес Условий. Тут каждая тропинка — это вопрос «если».",
      "if hp <= 0 then ... end — «если здоровья ноль или меньше, то...»",
      "Не забывай then после условия и end в конце. Без них лес тебя не выпустит.",
      "И запомни: = кладёт, == сравнивает. Это путают все. Даже я. Один раз. В 2019-м.",
    ],
    practice: {
      task: "Есть переменная key = true. Если key == true — выведи «Дверь открыта», иначе — «Закрыто».",
      starter: "local key = true\n",
      hint: 'if key == true then\n  print("Дверь открыта")\nelse\n  print("Закрыто")\nend',
      check(r) {
        const e = noErr(r);
        if (e) return { ok: false, msg: e };
        if (!codeHas(r, /\bif\b[\s\S]*\bthen\b[\s\S]*\bend\b/)) return { ok: false, msg: "Нужна конструкция if ... then ... end." };
        if (!codeHas(r, /\belse\b/)) return { ok: false, msg: "Добавь else для случая «Закрыто»." };
        if (!hasLine(r, /открыт/i)) return { ok: false, msg: "Ключ есть (true), значит должно вывестись «Дверь открыта»." };
        return { ok: true };
      },
    },
    homework: {
      id: "h4",
      title: "Магазин",
      task: "Создай переменную coins. Если монет 100 или больше — выведи «Покупаю меч!», если 50 или больше — «Покупаю щит», иначе — «Нужно больше монет». Попробуй разные числа!",
      starter: "-- Домашка №4\nlocal coins = 70\n",
      hint: 'if coins >= 100 then\n  print("Покупаю меч!")\nelseif coins >= 50 then\n  print("Покупаю щит")\nelse\n  print("Нужно больше монет")\nend',
      check(r) {
        const e = noErr(r);
        if (e) return { ok: false, msg: e };
        if (!codeHas(r, /\bif\b/) || !codeHas(r, /\belseif\b/) || !codeHas(r, /\belse\b/)) return { ok: false, msg: "Нужны все три части: if, elseif и else." };
        if (!r.out.length) return { ok: false, msg: "Ничего не вывелось — проверь print внутри условий." };
        return { ok: true };
      },
    },
    quiz: [
      { q: "Как проверить, что hp равно 0?", a: ["if hp == 0 then", "if hp = 0 then", "if hp is 0"], ok: 0, why: "Сравнивают двумя знаками ==." },
      { q: "Что пишут после условия в if?", a: ["then", "do", ":"], ok: 0, why: "if условие then ... end" },
      { q: "Как в Luau пишется «не равно»?", a: ["~=", "!=", "<>"], ok: 0, why: "В Luau «не равно» — это ~=" },
      { q: "local x = 5\nif x > 10 then print(\"A\") else print(\"B\") end\nЧто выведет?", a: ["B", "A", "Ничего"], ok: 0, why: "5 не больше 10, поэтому сработает else." },
    ],
  },
  {
    id: "l5",
    n: 5,
    title: "Циклы",
    topic: "for, while, wait",
    zone: "loop",
    card: `
<p><b>Цикл</b> повторяет код много раз, чтобы не копировать одно и то же.</p>
<pre>for i = 1, 5 do
  print("Шаг " .. i)
end</pre>
<p><code>i</code> — счётчик. Он по очереди становится 1, 2, 3, 4, 5.</p>
<p>Обратный отсчёт — с шагом <code>-1</code>:</p>
<pre>for i = 10, 1, -1 do
  print(i)
  wait(1)  -- пауза 1 секунда (в Roblox ещё пишут task.wait(1))
end</pre>
<p><code>while</code> повторяет, пока условие верно:</p>
<pre>local energy = 3
while energy > 0 do
  print("Работаю!")
  energy = energy - 1
end</pre>
<p>⚠️ Бесконечный цикл <code>while true do ... end</code> пиши <b>только с wait()</b> внутри, иначе игра зависнет.</p>`,
    talk: [
      "Городок Петля застрял во времени. Тут каждый день — один и тот же вторник.",
      "Это работа цикла. Цикл повторяет код снова и снова.",
      "for i = 1, 10 do ... end — повтори 10 раз, а i — номер повтора.",
      "Главное правило: в бесконечном цикле обязательно wait(). Без паузы всё зависнет. Как этот городок.",
    ],
    practice: {
      task: "С помощью for выведи числа от 1 до 10.",
      starter: "-- выведи числа 1..10 циклом for\n",
      hint: "for i = 1, 10 do\n  print(i)\nend",
      check(r) {
        const e = noErr(r);
        if (e) return { ok: false, msg: e };
        if (!codeHas(r, /\bfor\b/)) return { ok: false, msg: "Используй цикл for." };
        for (let i = 1; i <= 10; i++) if (!hasLine(r, new RegExp("(^|\\D)" + i + "(\\D|$)"))) return { ok: false, msg: `Не вижу числа ${i} в выводе.` };
        return { ok: true };
      },
    },
    homework: {
      id: "h5",
      title: "Запуск ракеты",
      task: "Сделай обратный отсчёт от 5 до 1 с паузой wait(1) после каждого числа, а потом выведи «Пуск!».",
      starter: "-- Домашка №5\n",
      hint: 'for i = 5, 1, -1 do\n  print(i)\n  wait(1)\nend\nprint("Пуск!")',
      check(r) {
        const e = noErr(r);
        if (e) return { ok: false, msg: e };
        const nums = r.out.map((l) => l.trim()).filter((l) => /^\d+$/.test(l)).map(Number);
        const want = [5, 4, 3, 2, 1];
        const idx = nums.join(",").indexOf(want.join(","));
        if (idx < 0) return { ok: false, msg: "Нужны числа 5, 4, 3, 2, 1 по порядку, каждое отдельным print." };
        if (!codeHas(r, /wait\s*\(/)) return { ok: false, msg: "Добавь паузу wait(1) внутри цикла." };
        if (!hasLine(r, /пуск/i)) return { ok: false, msg: "В конце выведи «Пуск!»." };
        return { ok: true };
      },
      time: 8,
    },
    quiz: [
      { q: "Сколько раз выполнится for i = 1, 3 do ... end?", a: ["3 раза", "1 раз", "4 раза"], ok: 0, why: "i будет 1, 2, 3 — три раза." },
      { q: "Что обязательно в бесконечном цикле while true do?", a: ["wait()", "print()", "Ничего"], ok: 0, why: "Без паузы wait() игра зависнет." },
      { q: "Как считать назад от 10 до 1?", a: ["for i = 10, 1, -1 do", "for i = 10, 1 do", "for i = 1, 10, -1 do"], ok: 0, why: "Третье число — шаг. -1 значит «назад»." },
      { q: "Какое слово начинает тело цикла?", a: ["do", "then", "begin"], ok: 0, why: "for ... do и while ... do. А then — у if." },
    ],
  },
  {
    id: "l6",
    n: 6,
    title: "Функции",
    topic: "function, return",
    zone: "robo",
    card: `
<p><b>Функция</b> — это своя команда. Один раз написал — используй сколько хочешь.</p>
<pre>local function greet(name)
  print("Привет, " .. name .. "!")
end

greet("Клод")
greet("Стажёр")</pre>
<ul>
<li><code>function</code> — «создаю команду»</li>
<li><code>name</code> — <b>параметр</b>: то, что дают функции внутрь</li>
<li><code>greet("Клод")</code> — <b>вызов</b>: «выполни команду»</li>
</ul>
<p><code>return</code> — вернуть ответ из функции:</p>
<pre>local function double(n)
  return n * 2
end
print(double(21))  -- 42</pre>
<p>В Roblox функции везде: «что делать, когда коснулись лавы», «как выдать награду» и так далее.</p>`,
    talk: [
      "Фабрика Функций. Роботы забыли все свои команды. Стоят и моргают.",
      "Функция — это своя команда. Пишешь один раз, используешь сколько угодно.",
      "local function greet(name) ... end — создали. greet(\"Боб\") — вызвали.",
      "А return — это когда функция что-то отвечает. Как калькулятор: дал числа — получил ответ.",
    ],
    practice: {
      task: "Создай функцию hello(), которая выводит «Я функция!», и вызови её 3 раза.",
      starter: "local function hello()\n  \nend\n",
      hint: 'local function hello()\n  print("Я функция!")\nend\n\nhello()\nhello()\nhello()',
      check(r) {
        const e = noErr(r);
        if (e) return { ok: false, msg: e };
        if (!codeHas(r, /\bfunction\b/)) return { ok: false, msg: "Нужна функция: local function hello() ... end" };
        if (r.out.filter((l) => /функц/i.test(l)).length < 3) return { ok: false, msg: "Функция должна вывести «Я функция!» 3 раза — вызови её трижды." };
        return { ok: true };
      },
    },
    homework: {
      id: "h6",
      title: "Калькулятор урона",
      task: "Напиши функцию damage(power, armor), которая возвращает (return) power - armor. Выведи результат damage(50, 8).",
      starter: "-- Домашка №6\n",
      hint: "local function damage(power, armor)\n  return power - armor\nend\n\nprint(damage(50, 8))",
      check(r) {
        const e = noErr(r);
        if (e) return { ok: false, msg: e };
        if (!codeHas(r, /\breturn\b/)) return { ok: false, msg: "Функция должна вернуть ответ через return." };
        if (!hasLine(r, /(^|\D)42(\D|$)/)) return { ok: false, msg: "damage(50, 8) должен дать 42 — выведи его через print." };
        return { ok: true };
      },
    },
    quiz: [
      { q: "Как вызвать функцию jump?", a: ["jump()", "function jump", "call jump"], ok: 0, why: "Вызов — имя и скобки: jump()" },
      { q: "Что делает return?", a: ["Возвращает ответ из функции", "Повторяет функцию", "Удаляет функцию"], ok: 0, why: "return отдаёт результат тому, кто вызвал." },
      { q: "local function f(x) return x + 1 end\nprint(f(4))", a: ["5", "4", "x + 1"], ok: 0, why: "x = 4, вернётся 4 + 1 = 5." },
      { q: "Зачем нужны функции?", a: ["Чтобы не повторять код", "Чтобы игра была медленнее", "Они не нужны"], ok: 0, why: "Один раз написал — вызываешь сколько хочешь." },
    ],
  },
  {
    id: "l7",
    n: 7,
    title: "Таблицы",
    topic: "{ }, ipairs",
    zone: "robo",
    card: `
<p><b>Таблица</b> — это коробка, в которой много значений. Например, инвентарь:</p>
<pre>local items = {"Меч", "Щит", "Зелье"}
print(items[1])   -- Меч (счёт с 1!)
print(#items)     -- 3, сколько всего
table.insert(items, "Ключ")</pre>
<p>Пройти по всем элементам — циклом <code>for ... in ipairs</code>:</p>
<pre>for i, item in ipairs(items) do
  print(i, item)
end</pre>
<p>Таблица-словарь хранит пары «ключ = значение»:</p>
<pre>local hero = {name = "Стажёр", hp = 100}
print(hero.name)
hero.hp = hero.hp - 10</pre>
<p>В Roblox <code>workspace:GetChildren()</code> возвращает таблицу всех объектов мира.</p>`,
    talk: [
      "Склад Таблиц. Тут роботы хранят всё по полочкам.",
      "Таблица — это много значений в одной переменной. Как инвентарь.",
      "items[1] — первая полка. В Luau счёт начинается с 1, а не с 0. Запомни, это важно!",
      "А for i, item in ipairs(items) do — пройтись по всем полкам по очереди.",
    ],
    practice: {
      task: "Создай таблицу из 3 своих любимых блюд и выведи второе.",
      starter: "local food = {}\n",
      hint: 'local food = {"Пицца", "Блины", "Суши"}\nprint(food[2])',
      check(r) {
        const e = noErr(r);
        if (e) return { ok: false, msg: e };
        if (!codeHas(r, /\{[^}]*,[^}]*,[^}]*\}/)) return { ok: false, msg: "Нужна таблица из трёх элементов через запятую: {\"А\", \"Б\", \"В\"}" };
        if (!codeHas(r, /\[\s*2\s*\]/)) return { ok: false, msg: "Второй элемент берут так: food[2]" };
        if (!r.out.length || r.out.some((l) => l === "nil")) return { ok: false, msg: "Выведи второй элемент через print." };
        return { ok: true };
      },
    },
    homework: {
      id: "h7",
      title: "Список друзей",
      task: "Сделай таблицу friends из 3 имён и выведи каждое имя циклом for ... in ipairs.",
      starter: "-- Домашка №7\n",
      hint: 'local friends = {"Боб", "Нубик", "Сова"}\nfor i, name in ipairs(friends) do\n  print(i .. ". " .. name)\nend',
      check(r) {
        const e = noErr(r);
        if (e) return { ok: false, msg: e };
        if (!codeHas(r, /\b(ipairs|pairs)\s*\(/)) return { ok: false, msg: "Используй for ... in ipairs(friends) do" };
        if (r.out.length < 3) return { ok: false, msg: "Должно вывестись хотя бы 3 имени." };
        return { ok: true };
      },
    },
    quiz: [
      { q: "local t = {\"а\", \"б\", \"в\"}\nprint(t[1])", a: ["а", "б", "nil"], ok: 0, why: "В Luau счёт с 1, значит t[1] — первый." },
      { q: "Что значит #items?", a: ["Сколько элементов", "Комментарий", "Первый элемент"], ok: 0, why: "# — длина таблицы." },
      { q: "Как добавить элемент в конец?", a: ["table.insert(t, x)", "t.add(x)", "t + x"], ok: 0, why: "table.insert добавляет в конец." },
      { q: "hero = {hp = 100}. Как прочитать hp?", a: ["hero.hp", "hero(hp)", "hp.hero"], ok: 0, why: "Через точку: hero.hp" },
    ],
  },
  {
    id: "l8",
    n: 8,
    title: "Детали: строим мир",
    topic: "Instance.new, Part",
    zone: "cube",
    card: `
<p>Всё в мире Roblox — это <b>объекты</b> (Instance). Кубик — это <b>Part</b>. Создадим его кодом:</p>
<pre>local part = Instance.new("Part")
part.Size = Vector3.new(4, 1, 4)      -- ширина, высота, глубина
part.Position = Vector3.new(0, 5, 0)  -- x, y (высота), z
part.Color = Color3.fromRGB(255, 0, 0)
part.Anchored = true                  -- приклеить, чтобы не падала
part.Parent = workspace               -- положить в мир!</pre>
<ul>
<li><code>Vector3.new(x, y, z)</code> — три числа: место или размер</li>
<li><code>Color3.fromRGB(красный, зелёный, синий)</code> — каждое от 0 до 255</li>
<li><code>Anchored = false</code> — деталь упадёт: работает гравитация</li>
<li>Пока нет <code>Parent = workspace</code>, детали в мире нет</li>
</ul>
<p>Ещё свойства: <code>part.Transparency = 0.5</code> (прозрачность), <code>part.Material = Enum.Material.Neon</code> (светится), <code>part.Shape = Enum.PartType.Ball</code> (шар).</p>
<p>Открой вкладку <b>Мир</b>, чтобы увидеть свою деталь.</p>`,
    talk: [
      "Кубоград. Это мир, собранный из деталей, как в настоящем Roblox. Только Глюк всё стёр.",
      "Каждый кубик тут — это Part. Мы создадим их кодом: Instance.new(\"Part\").",
      "Position — где стоит, Size — какого размера, Color — какого цвета.",
      "И самое важное: Anchored = true. Иначе твоя деталь просто упадёт. Гравитация не прощает.",
    ],
    practice: {
      task: "Создай красную деталь и положи её в мир (Parent = workspace). Посмотри на неё во вкладке «Мир».",
      starter: 'local part = Instance.new("Part")\n-- задай цвет и положи в workspace\n',
      hint: "part.Color = Color3.fromRGB(255, 0, 0)\npart.Anchored = true\npart.Parent = workspace",
      check(r) {
        const e = noErr(r);
        if (e) return { ok: false, msg: e };
        const ps = userParts(r);
        if (!ps.length) return { ok: false, msg: "В мире нет новой детали. Не забудь part.Parent = workspace" };
        if (!ps.some((p) => p.r > 0.55 && p.g < 0.45 && p.b < 0.45)) return { ok: false, msg: "Деталь есть, но не красная. Color3.fromRGB(255, 0, 0)" };
        return { ok: true };
      },
    },
    homework: {
      id: "h8",
      title: "Лестница в небо",
      task: "Циклом for от 1 до 5 построй лестницу: каждая ступенька выше (y = i) и дальше (x = i * 2). Не забудь Anchored = true!",
      starter: "-- Домашка №8\nfor i = 1, 5 do\n  \nend\n",
      hint: 'for i = 1, 5 do\n  local step = Instance.new("Part")\n  step.Size = Vector3.new(2, 1, 4)\n  step.Position = Vector3.new(i * 2, i, 0)\n  step.Anchored = true\n  step.Parent = workspace\nend',
      check(r) {
        const e = noErr(r);
        if (e) return { ok: false, msg: e };
        const ps = userParts(r);
        if (ps.length < 5) return { ok: false, msg: `Деталей в мире: ${ps.length}. Нужно хотя бы 5 ступенек.` };
        const ys = new Set(ps.map((p) => Math.round(p.y * 2)));
        if (ys.size < 5) return { ok: false, msg: "Ступеньки должны быть на разной высоте. Если они упали — поставь Anchored = true." };
        if (!codeHas(r, /\bfor\b/)) return { ok: false, msg: "Построй лестницу циклом for." };
        return { ok: true };
      },
    },
    quiz: [
      { q: "Как создать деталь?", a: ['Instance.new("Part")', 'Part.create()', 'new Part'], ok: 0, why: "Любой объект создают через Instance.new(\"Класс\")." },
      { q: "Зачем part.Anchored = true?", a: ["Чтобы деталь не падала", "Чтобы она светилась", "Чтобы удалить её"], ok: 0, why: "Anchored «приклеивает» деталь к месту." },
      { q: "Что делает part.Parent = workspace?", a: ["Кладёт деталь в мир", "Красит деталь", "Ничего"], ok: 0, why: "Без родителя workspace детали в мире нет." },
      { q: "Color3.fromRGB(0, 0, 255) — это какой цвет?", a: ["Синий", "Красный", "Зелёный"], ok: 0, why: "Числа — красный, зелёный, синий. Синий = 255." },
    ],
  },
  {
    id: "l9",
    n: 9,
    title: "События: игра реагирует",
    topic: "Touched, ClickDetector",
    zone: "cube",
    card: `
<p><b>Событие</b> — это «когда что-то случилось». <code>Touched</code> срабатывает, когда кто-то коснулся детали.</p>
<pre>local lava = Instance.new("Part")
lava.Anchored = true
lava.Color = Color3.fromRGB(255, 80, 0)
lava.Position = Vector3.new(0, 0.5, -10)
lava.Parent = workspace

lava.Touched:Connect(function(hit)
  local humanoid = hit.Parent:FindFirstChild("Humanoid")
  if humanoid then
    humanoid.Health = 0
  end
end)</pre>
<ul>
<li><code>:Connect(function(hit) ... end)</code> — «когда случится, выполни это»</li>
<li><code>hit</code> — часть тела, которая коснулась (например, нога)</li>
<li><code>hit.Parent</code> — весь персонаж, внутри него <code>Humanoid</code> со здоровьем</li>
</ul>
<p>Во вкладке <b>Мир</b> нажми на деталь — твой персонаж дойдёт и наступит на неё.</p>
<p>Клик по детали — через <b>ClickDetector</b>:</p>
<pre>local button = Instance.new("Part")
button.Anchored = true
button.Parent = workspace
local cd = Instance.new("ClickDetector")
cd.Parent = button
cd.MouseClick:Connect(function(player)
  button.Color = Color3.fromRGB(0, 255, 0)
end)</pre>`,
    talk: [
      "Теперь самое крутое. События! Это когда игра сама реагирует на игрока.",
      "lava.Touched:Connect(function(hit) ... end) — «когда кто-то коснулся лавы, выполни этот код».",
      "hit — это нога, которая наступила. hit.Parent — весь персонаж. А в нём Humanoid — здоровье.",
      "Humanoid.Health = 0 — и персонаж рассыпается. Классический kill brick из каждого обби!",
    ],
    practice: {
      task: "Сделай лаву: деталь, которая при касании ставит Health = 0. Проверь: нажми на неё во вкладке «Мир».",
      starter: 'local lava = Instance.new("Part")\nlava.Anchored = true\nlava.Color = Color3.fromRGB(255, 80, 0)\nlava.Position = Vector3.new(0, 0.5, -10)\nlava.Parent = workspace\n\n-- подключи событие Touched\n',
      hint: 'lava.Touched:Connect(function(hit)\n  local humanoid = hit.Parent:FindFirstChild("Humanoid")\n  if humanoid then\n    humanoid.Health = 0\n  end\nend)',
      async check(r) {
        const e = noErr(r);
        if (e) return { ok: false, msg: e };
        if (!codeHas(r, /Touched\s*:\s*Connect/)) return { ok: false, msg: "Нужно событие: lava.Touched:Connect(function(hit) ... end)" };
        const killed = await r.sim.touchEach((w) => w.avatar && w.avatar.dead);
        if (!killed) return { ok: false, msg: "Я наступил на все детали, но персонаж жив. Внутри события поставь humanoid.Health = 0" };
        return { ok: true };
      },
    },
    homework: {
      id: "h9",
      title: "Волшебная кнопка",
      task: "Сделай деталь с ClickDetector, которая при клике меняет свой цвет. Проверь во вкладке «Мир» — нажми на неё.",
      starter: "-- Домашка №9\n",
      hint: 'local button = Instance.new("Part")\nbutton.Anchored = true\nbutton.Parent = workspace\n\nlocal cd = Instance.new("ClickDetector")\ncd.Parent = button\ncd.MouseClick:Connect(function(player)\n  button.Color = Color3.fromRGB(math.random(0, 255), math.random(0, 255), math.random(0, 255))\nend)',
      async check(r) {
        const e = noErr(r);
        if (e) return { ok: false, msg: e };
        if (!codeHas(r, /ClickDetector/)) return { ok: false, msg: "Нужен ClickDetector внутри детали." };
        const changed = await r.sim.clickEachChanged();
        if (!changed) return { ok: false, msg: "Я кликнул по детали, но цвет не изменился. Внутри MouseClick поменяй Color." };
        return { ok: true };
      },
    },
    quiz: [
      { q: "Когда срабатывает Touched?", a: ["Когда кто-то коснулся детали", "Каждую секунду", "Когда игра закрылась"], ok: 0, why: "Touched — событие касания." },
      { q: "Как подключить код к событию?", a: [":Connect(function() ... end)", ".Run()", "=> function"], ok: 0, why: "Событие:Connect(функция)" },
      { q: "Где здоровье персонажа?", a: ["В Humanoid.Health", "В Part.Size", "В workspace.hp"], ok: 0, why: "У персонажа есть Humanoid со свойством Health." },
      { q: "Что нужно, чтобы по детали можно было кликнуть?", a: ["ClickDetector", "Anchored", "Material"], ok: 0, why: "ClickDetector ловит клики мышкой (и пальцем)." },
    ],
  },
  {
    id: "l10",
    n: 10,
    title: "Монеты и лидерборд",
    topic: "leaderstats, PlayerAdded",
    zone: "cube",
    card: `
<p>Как в настоящих симуляторах! Папка <code>leaderstats</code> внутри игрока показывает очки в таблице справа сверху.</p>
<pre>local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
  local stats = Instance.new("Folder")
  stats.Name = "leaderstats"
  stats.Parent = player

  local coins = Instance.new("IntValue")
  coins.Name = "Coins"
  coins.Parent = stats
end)

local coin = Instance.new("Part")
coin.Shape = Enum.PartType.Ball
coin.Color = Color3.fromRGB(255, 215, 0)
coin.Anchored = true
coin.Position = Vector3.new(6, 1, 0)
coin.Parent = workspace

coin.Touched:Connect(function(hit)
  local player = Players:GetPlayerFromCharacter(hit.Parent)
  if player then
    player.leaderstats.Coins.Value += 1
    coin:Destroy()
  end
end)</pre>
<ul>
<li><code>PlayerAdded</code> — событие «игрок зашёл в игру»</li>
<li><code>IntValue</code> — коробка для целого числа, её видно в таблице</li>
<li><code>GetPlayerFromCharacter</code> — узнать игрока по его персонажу</li>
<li><code>coin:Destroy()</code> — удалить монету</li>
</ul>
<p>Так устроены монеты почти в каждой игре Roblox. И в «Симуляторе Бункера» тоже!</p>`,
    talk: [
      "Последний урок Кубограда. Монеты и таблица лидеров. Как в каждом симуляторе!",
      "Когда игрок заходит, срабатывает Players.PlayerAdded. В этот момент мы создаём ему папку leaderstats.",
      "В папке — IntValue с именем Coins. Roblox сам покажет его в таблице справа сверху.",
      "А монета при касании делает Coins.Value += 1 и исчезает через :Destroy(). Это и есть геймплей!",
    ],
    practice: {
      task: "Сделай leaderstats с монетами Coins и монету, которая при касании даёт +1. Проверь в «Мире»: нажми на монету.",
      starter: 'local Players = game:GetService("Players")\n\nPlayers.PlayerAdded:Connect(function(player)\n  -- создай папку leaderstats и IntValue Coins\nend)\n',
      hint: "Посмотри пример в шпаргалке: там вся программа целиком. Перепиши её своими руками — так запоминается лучше.",
      async check(r) {
        const e = noErr(r);
        if (e) return { ok: false, msg: e };
        if (!codeHas(r, /leaderstats/)) return { ok: false, msg: "Нужна папка с именем leaderstats." };
        if (!r.world.stats.length) return { ok: false, msg: "Таблица лидеров пустая. Создай IntValue внутри leaderstats (в PlayerAdded)." };
        const got = await r.sim.touchEach((w) => w.stats.some((s) => +s.value >= 1));
        if (!got) return { ok: false, msg: "Я наступил на детали, но монет не прибавилось. В Touched сделай player.leaderstats.Coins.Value += 1" };
        return { ok: true };
      },
    },
    homework: {
      id: "h10",
      title: "Своя мини-игра",
      task: "Придумай свою мини-игру! Используй хотя бы 3 вещи из уроков: переменные, if, циклы, функции, детали, события, leaderstats. Например: дорожка из монет и лава между ними. Покажи Клоду — он оценит.",
      starter: "-- Домашка №10: моя игра\n",
      hint: "Идея: циклом for поставь 5 монет в ряд (Position = Vector3.new(i * 4, 1, 0)), каждой подключи Touched, а между ними — детали-лаву.",
      review: true,
      check(r) {
        const e = noErr(r);
        if (e) return { ok: false, msg: e };
        const feats = [
          [/\blocal\b/, "переменные"], [/\bif\b/, "условия"], [/\b(for|while)\b/, "циклы"], [/\bfunction\b/, "функции"],
          [/Instance\.new/, "детали"], [/:\s*Connect/, "события"], [/leaderstats/, "leaderstats"],
        ].filter(([re]) => codeHas(r, re));
        if (feats.length < 3) return { ok: false, msg: `Пока использовано: ${feats.map((f) => f[1]).join(", ") || "ничего"}. Нужно хотя бы 3 разные вещи из уроков.` };
        return { ok: true, msg: "Использовано: " + feats.map((f) => f[1]).join(", ") };
      },
    },
    quiz: [
      { q: "Как называется папка для таблицы лидеров?", a: ["leaderstats", "LeaderBoard", "stats"], ok: 0, why: "Roblox ищет папку именно с именем leaderstats." },
      { q: "Какое событие срабатывает, когда игрок зашёл?", a: ["Players.PlayerAdded", "workspace.Touched", "game.Start"], ok: 0, why: "PlayerAdded — «игрок добавлен в игру»." },
      { q: "Как удалить монету?", a: ["coin:Destroy()", "coin = nil", "delete coin"], ok: 0, why: ":Destroy() убирает объект из игры." },
      { q: "Coins.Value += 1 — что это значит?", a: ["Прибавить 1 монету", "Сделать монеты равными 1", "Ошибка"], ok: 0, why: "+= 1 — прибавить один к тому, что было." },
    ],
  },
];

const LESSON = Object.fromEntries(LESSONS.map((l) => [l.id, l]));
const HOMEWORK = Object.fromEntries(LESSONS.map((l) => [l.homework.id, { ...l.homework, lesson: l }]));

// Правила, которые может менять Клод (и офлайн-команды)
const RULE_DEFAULTS = {
  speed: 1,
  maxHpBonus: 0,
  attackBonus: 0,
  enemyDamage: 1,
  bulletSpeed: 1,
  godMode: false,
  weather: "none",
  worldHue: 0,
  playerColor: "",
  playerSize: 1,
  hat: "none",
  night: false,
  encounters: true,
  claudeFollows: true,
  textSpeed: 2,
};
