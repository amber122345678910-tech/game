/* ===== 05e_codex.js ===== */
// Кодекс — режим, в котором Амиго сам программирует игры. Здесь его знания:
// словарь предметов (слово → эмодзи и роль), миры, жанры (готовые «рецепты» игр) и приёмы,
// а также понимание описания игры, сборка чертежа (spec), правки словами и проверка новых приёмов.
// Роли: h — может быть героем, g — хороший предмет, b — враг или препятствие, n — что угодно, p — платформа.
const CODEX_WORDS = [
  [['кот', 'кошка', 'котик', 'котенок', 'кошечка', 'котэ', 'котята', 'кошек'], '🐱', 'h'], [['собака', 'пес', 'щенок', 'песик', 'пёсик', 'щенки', 'щенята', 'псы'], '🐶', 'h'], [['мышь', 'мышка', 'мышонок', 'мышата'], '🐭', 'h'],
  [['хомяк', 'хомячок'], '🐹', 'h'], [['кролик', 'заяц', 'зайчик', 'зайка', 'крольчонок', 'зайцы', 'крольчата'], '🐰', 'h'], [['лиса', 'лисица', 'лисенок', 'лисичка', 'лисята'], '🦊', 'h'],
  [['медведь', 'мишка', 'медвежонок', 'медвежата'], '🐻', 'h'], [['панда'], '🐼', 'h'], [['коала'], '🐨', 'h'], [['тигр', 'тигренок', 'тигрята'], '🐯', 'h'], [['лев', 'львенок', 'львы', 'львята'], '🦁', 'h'],
  [['корова', 'бык', 'теленок'], '🐮', 'n'], [['свинья', 'поросенок', 'свинка', 'хрюшка', 'поросята'], '🐷', 'h'], [['лягушка', 'лягушонок', 'жаба'], '🐸', 'h'],
  [['обезьяна', 'обезьянка', 'мартышка'], '🐵', 'h'], [['курица', 'цыпленок', 'петух', 'курочка', 'цыплята'], '🐔', 'h'], [['пингвин', 'пингвиненок', 'пингвинята'], '🐧', 'h'],
  [['птица', 'птичка', 'воробей', 'синица', 'птенец'], '🐦', 'h'], [['утка', 'утенок', 'уточка', 'утята'], '🦆', 'h'], [['сова', 'совенок', 'филин'], '🦉', 'h'],
  [['орел', 'ястреб', 'сокол', 'орлы'], '🦅', 'h'], [['попугай'], '🦜', 'h'], [['волк', 'волчонок', 'волчата'], '🐺', 'b'], [['лошадь', 'конь', 'пони', 'лошадка'], '🐴', 'h'],
  [['единорог'], '🦄', 'h'], [['пчела', 'пчелка'], '🐝', 'h'], [['бабочка'], '🦋', 'h'], [['улитка'], '🐌', 'n'], [['змея', 'змей', 'кобра', 'гадюка'], '🐍', 'b'],
  [['черепаха', 'черепашка'], '🐢', 'h'], [['ящерица', 'геккон'], '🦎', 'h'], [['крокодил', 'аллигатор'], '🐊', 'b'], [['динозавр', 'дино', 'тираннозавр', 'динозаврик'], '🦖', 'h'],
  [['дракон', 'дракончик'], '🐉', 'h'], [['кит', 'китенок', 'китята'], '🐳', 'h'], [['дельфин'], '🐬', 'h'], [['рыба', 'рыбка', 'рыбешка', 'карась'], '🐟', 'g'], [['акула'], '🦈', 'b'],
  [['осьминог'], '🐙', 'h'], [['краб', 'крабик'], '🦀', 'b'], [['медуза'], '🪼', 'b'], [['паук', 'паучок', 'паучки'], '🕷️', 'b'], [['муха', 'мушка'], '🪰', 'b'], [['комар'], '🦟', 'b'],
  [['жук', 'жучок', 'жучки'], '🪲', 'n'], [['муравей'], '🐜', 'n'], [['слон', 'слоненок', 'слонята'], '🐘', 'h'], [['жираф'], '🦒', 'h'], [['зебра'], '🦓', 'h'], [['верблюд'], '🐫', 'h'],
  [['олень', 'лось'], '🦌', 'h'], [['белка', 'бельчонок', 'бельчата'], '🐿️', 'h'], [['ежик', 'еж'], '🦔', 'h'], [['коза', 'козел'], '🐐', 'n'], [['овца', 'баран', 'ягненок', 'овечка', 'ягнята'], '🐑', 'n'],
  [['кенгуру'], '🦘', 'h'], [['енот'], '🦝', 'h'], [['ленивец'], '🦥', 'h'], [['выдра'], '🦦', 'h'], [['бобр'], '🦫', 'h'], [['тюлень', 'нерпа'], '🦭', 'h'], [['фламинго'], '🦩', 'h'],
  [['мамонт'], '🦣', 'h'], [['божья коровка', 'коровка', 'божьи коровки'], '🐞', 'n'], [['летучая мышь'], '🦇', 'b'], [['скорпион'], '🦂', 'b'], [['таракан'], '🪳', 'b'],
  [['яблоко', 'яблочко'], '🍎', 'g'], [['груша'], '🍐', 'g'], [['банан'], '🍌', 'g'], [['апельсин', 'мандарин'], '🍊', 'g'], [['клубника', 'ягода', 'ягодка', 'малина'], '🍓', 'g'],
  [['вишня', 'черешня'], '🍒', 'g'], [['виноград'], '🍇', 'g'], [['арбуз'], '🍉', 'g'], [['ананас'], '🍍', 'g'], [['морковь', 'морковка'], '🥕', 'g'], [['кукуруза'], '🌽', 'g'],
  [['гриб', 'грибок', 'грибочек'], '🍄', 'g'], [['сыр'], '🧀', 'g'], [['хлеб', 'булка', 'батон', 'булочка'], '🍞', 'g'], [['пицца'], '🍕', 'g'], [['бургер', 'гамбургер'], '🍔', 'g'],
  [['картошка', 'картофель', 'фри'], '🍟', 'g'], [['сосиска', 'хотдог'], '🌭', 'g'], [['пончик'], '🍩', 'g'], [['печенье', 'печенька'], '🍪', 'g'], [['торт', 'тортик', 'пирожное'], '🍰', 'g'],
  [['конфета', 'конфетка', 'леденец', 'сладость'], '🍬', 'g'], [['шоколад', 'шоколадка'], '🍫', 'g'], [['мороженое', 'мороженка', 'пломбир'], '🍦', 'g'], [['мед'], '🍯', 'g'],
  [['молоко'], '🥛', 'g'], [['сок', 'лимонад'], '🧃', 'g'], [['яйцо', 'яичко'], '🥚', 'g'], [['кость', 'косточка'], '🦴', 'g'], [['орех', 'орешек', 'желудь', 'орешки'], '🌰', 'g'],
  [['лимон'], '🍋', 'g'], [['персик'], '🍑', 'g'], [['кокос'], '🥥', 'g'], [['помидор'], '🍅', 'g'], [['огурец', 'огурцы'], '🥒', 'g'], [['суши', 'ролл'], '🍣', 'g'], [['кекс', 'кексик', 'капкейк'], '🧁', 'g'],
  [['монета', 'монетка', 'деньги', 'золото', 'денежка'], '🪙', 'g'], [['звезда', 'звездочка'], '⭐', 'g'], [['алмаз', 'бриллиант', 'кристалл', 'самоцвет'], '💎', 'g'],
  [['сердце', 'сердечко'], '❤️', 'g'], [['подарок'], '🎁', 'g'], [['ключ', 'ключик'], '🔑', 'g'], [['корона'], '👑', 'g'], [['кубок', 'приз', 'трофей'], '🏆', 'g'],
  [['шарик', 'воздушный шар', 'шар'], '🎈', 'g'], [['цветок', 'цветочек', 'роза', 'ромашка', 'тюльпан', 'цветы'], '🌸', 'g'], [['лист', 'листик', 'листок'], '🍃', 'n'],
  [['снежинка', 'снежок', 'снежки'], '❄️', 'n'], [['капля', 'капелька'], '💧', 'n'], [['мяч', 'мячик'], '⚽', 'g'], [['книга', 'книжка'], '📕', 'g'], [['батарейка', 'энергия'], '🔋', 'g'],
  [['зелье', 'эликсир'], '🧪', 'g'], [['пузырь', 'пузырек', 'пузырик'], '🫧', 'g'], [['ракушка', 'жемчуг', 'жемчужина'], '🐚', 'g'], [['елка', 'елочка'], '🎄', 'n'], [['тыква'], '🎃', 'n'],
  [['метеорит', 'астероид', 'комета', 'метеор', 'метеориты'], '☄️', 'b'], [['бомба', 'бомбочка', 'мина'], '💣', 'b'], [['камень', 'булыжник', 'скала', 'валун', 'камни'], '🪨', 'b'], [['кактус'], '🌵', 'b'],
  [['огонь', 'пламя', 'костер', 'огонек', 'огня', 'огоньки'], '🔥', 'b'], [['молния'], '⚡', 'b'], [['туча', 'облако', 'облачко'], '☁️', 'p'], [['шип', 'колючка'], '🔺', 'b'], [['бревно', 'полено'], '🪵', 'b'],
  [['стена', 'стенка', 'забор', 'кирпич'], '🧱', 'b'], [['бочка'], '🛢️', 'b'], [['вирус', 'микроб', 'бактерия'], '🦠', 'b'], [['мусор'], '🗑️', 'b'], [['стрела'], '🏹', 'b'],
  [['лед', 'льдина', 'айсберг', 'льда'], '🧊', 'p'], [['гора'], '⛰️', 'b'], [['дерево', 'деревце'], '🌳', 'b'], [['торнадо', 'смерч', 'ураган'], '🌪️', 'b'], [['пила'], '🪚', 'b'],
  [['призрак', 'привидение', 'приведение'], '👻', 'b'], [['зомби'], '🧟', 'b'], [['пришелец', 'инопланетянин', 'инопланетник', 'пришельцы'], '👾', 'b'], [['нло', 'тарелка'], '🛸', 'b'],
  [['монстр', 'чудовище', 'чудище'], '👹', 'b'], [['вампир'], '🧛', 'b'], [['ведьма'], '🧙‍♀️', 'b'], [['скелет'], '💀', 'b'], [['робот', 'робо', 'андроид'], '🤖', 'h'],
  [['пират'], '🏴‍☠️', 'b'], [['ниндзя'], '🥷', 'h'], [['рыцарь'], '🤺', 'h'], [['принцесса'], '👸', 'h'], [['принц', 'король'], '🤴', 'h'], [['полицейский', 'полиция'], '👮', 'b'],
  [['вор', 'грабитель', 'бандит'], '🦹', 'b'], [['супергерой', 'герой'], '🦸', 'h'], [['маг', 'волшебник', 'колдун'], '🧙', 'h'], [['фея'], '🧚', 'h'], [['русалка'], '🧜‍♀️', 'h'],
  [['тролль'], '🧌', 'b'], [['мальчик', 'пацан'], '👦', 'h'], [['девочка'], '👧', 'h'], [['человек', 'человечек'], '🧍', 'h'], [['космонавт', 'астронавт'], '🧑‍🚀', 'h'],
  [['пожарный'], '🧑‍🚒', 'h'], [['повар'], '🧑‍🍳', 'h'], [['снеговик'], '⛄', 'h'], [['санта', 'дед мороз'], '🎅', 'h'], [['клоун'], '🤡', 'n'], [['колобок', 'смайлик'], '😀', 'h'],
  [['машина', 'машинка', 'автомобиль', 'тачка'], '🚗', 'h'], [['грузовик'], '🚚', 'b'], [['автобус'], '🚌', 'b'], [['такси'], '🚕', 'b'], [['мотоцикл', 'байк'], '🏍️', 'h'],
  [['велосипед', 'велик'], '🚲', 'h'], [['поезд', 'паровоз'], '🚂', 'h'], [['самолет', 'самолетик'], '✈️', 'h'], [['вертолет'], '🚁', 'h'],
  [['ракета', 'звездолет', 'корабль'], '🚀', 'h'], [['лодка', 'кораблик', 'яхта', 'катер'], '⛵', 'h'], [['скейт', 'скейтборд'], '🛹', 'n'], [['платформа', 'ступенька', 'полка'], '▬', 'p'],
  [['амиго'], '🙂', 'h'],
];
// миры: оформление и фон
const CODEX_THEMES = {
  space: { name: 'космос', re: /космос|космич|галактик|(^|\s)марс|на луне|планет|звездн/, bg: ['#0B1033', '#1C2B66'], deco: 'stars', dark: true },
  water: { name: 'под водой', re: /под вод|подвод|океан|(^|\s)мор[еяю]|морск|на дне|аквариум|в реке|озер/, bg: ['#0A4C86', '#1FA2DB'], deco: 'bubbles', dark: true },
  forest: { name: 'лес', re: /(^|\s)лес|лесн|джунгл|чащ/, bg: ['#2D7A4D', '#9AD06F'], deco: 'leaves', dark: false },
  city: { name: 'город', re: /город|улиц|шоссе|трасс|дорог|мегаполис/, bg: ['#56678A', '#A9BCD6'], deco: 'city', dark: false },
  desert: { name: 'пустыня', re: /пустын|сахар|песк|песок|египет/, bg: ['#E7B46B', '#F8E2A9'], deco: 'dunes', dark: false },
  winter: { name: 'зима', re: /зим|снег|север|антаркт|арктик|(^|\s)(лед|льд)|морозн/, bg: ['#A9D9F2', '#EEF8FF'], deco: 'snow', dark: false },
  night: { name: 'ночь', re: /ночь|ночн|темн|в темноте|полночь/, bg: ['#120B2E', '#33236A'], deco: 'night', dark: true },
  castle: { name: 'замок', re: /замок|замк|подземел|пещер|крепост|данж/, bg: ['#34383F', '#6B7280'], deco: 'bricks', dark: true },
  lava: { name: 'вулкан', re: /вулкан|лав[аеуы]|огненн|ад(\s|$)/, bg: ['#360808', '#B33A0E'], deco: 'embers', dark: true },
  candy: { name: 'сладкий мир', re: /конфетн|сладк|леденц|шоколадн|кондитер/, bg: ['#FFC4E1', '#FFF1F8'], deco: 'sprinkles', dark: false },
  farm: { name: 'деревня', re: /ферм|деревн|огород|(^|\s)пол[ея](\s|$)|луг/, bg: ['#8DD16E', '#E6F7D5'], deco: 'flowers', dark: false },
  sky: { name: 'небо', re: /небо|небес|облак/, bg: ['#7CC8F5', '#E6F6FF'], deco: 'clouds', dark: false },
};
// жанры: как устроена игра и что подставить, если в описании чего-то нет
const CODEX_GENRES = {
  catch: { name: 'ловилка', suffix: 'ловец', control: 'horizontal', hero: '🧺', good: '⭐', bad: '💣', icon: '🧺',
    help: 'Двигай героя стрелками, мышкой или пальцем. Лови {good}, а {bad} не лови!',
    kw: /(^|\s)лов[иляюе]|поймай|поймать|падают|падающ|корзин|сыплются/, w: 0.5 },
  dodge: { name: 'уворачивалка', suffix: 'выживатель', control: 'free', hero: 'amigo', good: '⭐', bad: '☄️', icon: '💨',
    help: 'Веди героя мышкой, пальцем или стрелками. Уворачивайся от {bad} и собирай {good}.', pace: 0.8,
    kw: /уворач|увернись|увернуться|избега|спаса\S* от|выжив|убега\S* от|убегай|прячь|не дай/, w: 0.55 },
  shooter: { name: 'стрелялка', suffix: 'стрелок', control: 'horizontal', hero: '🚀', good: '⭐', bad: '👾', icon: '🔫',
    help: 'Двигай героя, он стреляет сам. Сбивай {bad}, лови {good}.',
    kw: /стрел|сбива|пушк|лазер|(^|\s)тир(\s|$)|шутер|отстрел|уничтож|защища\S* (планету|землю|город)|пиу/, w: 0.65 },
  runner: { name: 'бегалка', suffix: 'бегун', control: 'runner', hero: 'amigo', good: '🪙', bad: '🌵', icon: '🏃',
    help: 'Нажимай пробел, стрелку вверх или на экран, чтобы прыгать через {bad}. Собирай {good}.', pace: 0.9,
    kw: /прыга\S* через|перепрыг|(^|\s)беж|(^|\s)бег(\s|а|ать|ает)|раннер|паркур|динозаврик|бегун/, w: 0.55 },
  flappy: { name: 'леталка', suffix: 'летун', control: 'flappy', hero: '🐤', good: '🪙', bad: '', icon: '🐤',
    help: 'Нажимай на экран или пробел, чтобы взлетать. Пролетай между препятствиями.',
    kw: /флэппи|флеппи|flappy|между|пролет|лети(\s|$)|не врезайся/, w: 0.55 },
  topdown: { name: 'собиралка', suffix: 'собиратель', control: 'topdown', hero: 'amigo', good: '🪙', bad: '👻', icon: '🗺️',
    help: 'Ходи стрелками или веди пальцем. Собери все {good}, а от {bad} убегай.',
    kw: /лабиринт|пакман|pacman|собери все|найди все|ходилк|гоня\S* за|бегай по|ходи по|собира\S*.*убега|призрак/, w: 0.6 },
  jumper: { name: 'прыгалка', suffix: 'прыгун', control: 'jumper', hero: '🐸', good: '⭐', bad: '👾', icon: '🦘',
    help: 'Двигай героя влево и вправо. Он сам прыгает по платформам. Забирайся как можно выше!',
    kw: /прыга\S* по|платформ|дудл|doodle|выше и выше|забир|вверх по|по облакам|по льдин|лезь вверх/, w: 0.6 },
  tapper: { name: 'кликер', suffix: 'ловкач', control: 'tap', hero: '', good: '🎈', bad: '💣', icon: '👆',
    help: 'Нажимай на {good}, пока они не исчезли. На {bad} не нажимай! Есть 60 секунд.',
    kw: /лопа|кликер|кликай|нажима\S* на|тыка|крот|реакци|кто быстрее наж/, w: 0.6 },
  racer: { name: 'гонки', suffix: 'гонщик', control: 'lanes', hero: '🚗', good: '🪙', bad: '🚙', icon: '🏁',
    help: 'Перестраивайся стрелками или касанием слева и справа. Объезжай {bad}, собирай {good}.',
    kw: /гонк|гоноч|трасс|шоссе|дорог|объезжа|(^|\s)машин|мотоцикл|гонщик|полос/, w: 0.5 },
};
// известные приёмы: слова в описании → что добавить в игру
const CODEX_FEATURES = [
  { id: 'boss', re: /босс|главар|финальн\S* враг/, name: 'босс' },
  { id: 'powers', re: /бонус|усилен|суперсил|power|прокачк|способност/, name: 'бонусы' },
  { id: 'shield', re: /(^|\s)щит/, name: 'щит' }, { id: 'magnet', re: /магнит/, name: 'магнит' },
  { id: 'slow', re: /замедл/, name: 'замедление времени' }, { id: 'double', re: /двойн\S* очк|удвоен|x2|х2/, name: 'двойные очки' },
  { id: 'levels', re: /уровн|level/, name: 'уровни' },
  { id: 'timer', re: /на время|за минуту|таймер|за (\d+) секунд|за (\d+) с(\s|$)/, name: 'игра на время' },
  { id: 'portal', re: /портал|телепорт/, name: 'порталы' },
  { id: 'shoot', re: /стреля|пул[июя]|лазер|пушк/, name: 'стрельба' },
  { id: 'djump', re: /двойн\S* прыж|прыга\S* дважды/, name: 'двойной прыжок' },
  { id: 'gravity', re: /гравитац\S* наоборот|антигравитац|вверх ногами|на потолке/, name: 'гравитация наоборот' },
  { id: 'wrap', re: /без стен|сквозь стен|через стен/, name: 'проход сквозь стены' },
  { id: 'chasers', re: /гоня\S* за|преследу|догоня/, name: 'преследователи' },
  { id: 'bombs', re: /взрыва\S* (всех|врагов)|бомбу (можно|кидать)|супер.?взрыв/, name: 'взрыв' },
  { id: 'hearts', re: /аптечк|сердечк\S* (лечат|дают)|лечилк/, name: 'аптечки' },
];
const CODEX_LEVELS = {
  medium: { name: 'Средний', fx: { particles: false, sound: true, shake: false, text: true, banner: true, parallax: false, combo: false } },
  high: { name: 'Высокий', fx: { particles: true, sound: true, shake: true, text: true, banner: true, parallax: true, combo: true } },
  ultra: { name: 'Ультра', fx: { particles: true, sound: true, shake: true, text: true, banner: true, parallax: true, combo: true } },
};
// примеры описаний для обучения нейросети Кодекса ({h} — герой, {g} — хороший предмет, {b} — враг, {p} — платформа)
const CODEX_TRAIN = {
  catch: ['игра где {h} ловит {g}', '{h} ловит {g}', 'ловить {g}', 'собирать падающие {g}', 'лови {g} и не лови {b}', 'игра про {h} который ловит {g}', 'надо ловить {g} корзинкой',
    'падают {g} а ты их ловишь', 'с неба падают {g}', '{h} собирает {g} которые падают', 'поймай {g}', 'ловилка', 'игра поймай {g}', 'ловить падающие {g} и уворачиваться от {b}',
    'сверху падают {g} и {b}', 'лови {g} в корзину', '{h} ловит {g} под водой', 'игра где падают {g}', 'собери падающие {g}', 'ловить {g} пока не упали'],
  dodge: ['уворачивайся от {b}', '{h} уворачивается от {b}', 'убегай от {b}', 'избегай {b}', 'летят {b} а ты уворачиваешься', 'выживи как можно дольше', 'не дай {b} тебя задеть',
    'игра на выживание', '{h} спасается от {b}', 'увернись от {b}', 'прячься от {b}', '{b} летят со всех сторон', 'уклоняйся от {b}', '{h} убегает от {b}', 'выживалка',
    'со всех сторон летят {b} а {h} должен выжить', 'продержись как можно дольше', 'уворачиваться от падающих {b}', '{h} в космосе уворачивается от {b}', 'не попадись {b}'],
  shooter: ['стрелялка', '{h} стреляет в {b}', 'сбивай {b}', 'космический корабль стреляет в пришельцев', 'стреляй по {b}', 'защищай планету от {b}', 'тир', 'уничтожай {b}',
    'отстреливайся от {b}', 'шутер', 'игра где надо стрелять', '{h} стреляет лазером', 'сбивать {b} из пушки', '{h} защищает город от {b}', 'стрелять во врагов', 'космическая стрелялка',
    'уничтожь всех {b}', 'пиу пиу по {b}', '{h} отбивается от {b}', 'война с {b}'],
  runner: ['{h} прыгает через {b}', 'бегалка', 'раннер', 'беги и прыгай через {b}', '{h} бежит и перепрыгивает {b}', 'прыгать через препятствия', 'как динозаврик в гугле',
    'бесконечный бег', 'паркур', '{h} бежит по дороге', 'перепрыгивай {b}', '{h} бежит и собирает {g}', 'бег с препятствиями', 'прыгай через {b} и собирай {g}', '{h} бегун',
    'беги как можно дальше', 'прыгать через ямы и {b}', '{h} мчится и прыгает', 'игра бег', 'убегать и перепрыгивать'],
  flappy: ['{h} летит между {b}', 'летать между трубами', 'как флэппи бёрд', '{h} летает и не врезается', 'пролетай между {b}', 'вертолёт летит через {b}', 'лети и не падай',
    'нажимай чтобы лететь вверх', 'flappy bird', '{h} летит через препятствия', 'пролететь между {b}', 'леталка', '{h} машет крыльями', 'лети между столбами', 'не врезайся в {b}',
    'игра где надо летать', '{h} летит и собирает {g}', 'полёт между {b}', 'птичка летит между трубами', 'летать и уворачиваться от стен'],
  topdown: ['собирай {g} и убегай от {b}', 'лабиринт', 'как пакман', '{h} ходит и собирает {g}', 'бегай по полю и собирай {g}', 'собери все {g}', 'найди все {g}', 'ходилка',
    '{b} гоняются за {h}', '{h} собирает {g} а {b} мешают', 'пакман', 'собирать {g} по всей карте', '{h} ищет {g}', 'ходи и собирай {g}', 'за {h} гоняются {b}',
    'собери все {g} и не попадись {b}', 'бегать от {b} и собирать {g}', '{h} в лабиринте', 'игра собирать {g} на поле', 'исследуй карту'],
  jumper: ['{h} прыгает по {p} вверх', 'прыгай по платформам', 'как дудл джамп', 'забирайся как можно выше', 'прыжки по облакам', '{h} прыгает по {p}', 'прыгать вверх по ступенькам',
    'лезь вверх', 'прыгалка вверх', '{h} скачет по {p}', 'выше и выше', 'прыгать по льдинам', 'doodle jump', 'запрыгни как можно выше', '{h} прыгает с платформы на платформу',
    'прыгать по облакам до неба', 'прыгай вверх и собирай {g}', 'платформер вверх', 'подпрыгивай выше', 'прыжки вверх'],
  tapper: ['лопай {g}', 'нажимай на {g}', 'кликер', 'бей кротов', 'тыкай на {g} пока не исчезли', 'лопать шарики', 'кто быстрее нажмёт', 'игра на реакцию', 'поймай {g} пальцем',
    'кликай по {g}', 'лопай пузыри', 'нажимай на {g} и не нажимай на {b}', 'ударь {b}', 'лопать воздушные шары на время', 'появляются {g} и надо успеть нажать', 'тапалка',
    'нажми на всех {g}', 'игра на скорость нажатия', 'лопай {g} за минуту', 'ловить {g} касанием'],
  racer: ['гонки', 'гоночки', '{h} едет по дороге и объезжает {b}', 'машинка уворачивается от машин', 'гонка на трассе', 'объезжай {b}', 'езди по полосам', 'мотоцикл мчится по шоссе',
    'гонки на машинах', '{h} едет по трассе', 'перестраивайся и объезжай {b}', 'гонщик', 'машина едет и собирает {g}', 'гонки по городу', 'не врежься в машины', 'гоняй по шоссе',
    '{h} мчится по дороге', 'гонки с препятствиями', 'объезжать {b} на дороге', 'трасса и машины'],
};

const Codex = (() => {
  const low = s => String(s).toLowerCase().replace(/ё/g, 'е');
  // словарь по основам слов
  const index = new Map(), multi = [];
  for (const [al, emoji, role] of CODEX_WORDS) {
    const entry = { name: al[0], emoji, role };
    for (const a of al) {
      const ws = Text.words(a);
      if (ws.length > 1) multi.push({ st: ws.map(Text.stem), entry });
      else if (ws.length) index.set(Text.stem(ws[0]), entry);
    }
  }
  const THEME_WORDS = new Set(['космос', 'вода', 'море', 'океан', 'лес', 'город', 'пустын', 'зима', 'ночь', 'замок', 'небо', 'поле', 'дорог', 'трасс', 'уровн', 'игр', 'игра', 'очк', 'жизн', 'врем', 'секунд', 'минут']
    .map(Text.stem));
  const STOP = new Set(['игр', 'игра', 'игру', 'игры', 'сделай', 'создай', 'напиши', 'придумай', 'про', 'где', 'который', 'которая', 'которые', 'котор', 'и', 'а', 'но', 'в', 'на', 'от', 'по', 'за',
    'с', 'со', 'из', 'к', 'у', 'о', 'об', 'чтобы', 'надо', 'нужно', 'можно', 'есть', 'очень', 'много', 'мне', 'хочу', 'пусть', 'будет', 'тоже', 'еще', 'ещё', 'как', 'не', 'это', 'его', 'её', 'их',
    'там', 'тут', 'когда', 'чтоб', 'всех', 'все', 'всё', 'весь', 'при', 'для', 'до', 'или', 'же', 'бы', 'ну', 'вот', 'тебе', 'ты', 'я', 'он', 'она', 'они', 'мы', 'вы', 'себя', 'свою', 'своих', 'такую']);
  const COLLECT = /(^|\s)(лов(и|ит|ят|ить|им|ишь|лю)|поймай\S*|поймать|собира\S*|собери\S*|собрать|ест|ешь|кушает|ищет|ищи|найди|хватает|хватай|копит|достает|лопа\S*|нажимай на|кликай по|тыкай на|ловля)$/;
  const COLLECT2 = /(^|\s)(лов(и|ит|ят|ить|им)|собира\S*|собери\S*) \S+$/;
  const VERB_END = /(ть|ться|ет|ют|ут|ит|ят|ешь|ишь|ем|им|ете|ите|ал|ял|ил|ел|ла|ло|ли|ай|яй|ей|уй|йся|ется|ются|ится|ятся)$/;
  const ADJ_END = /(ый|ий|ой|ая|яя|ое|ее|ые|ие|ого|его|ому|ему|ую|юю|ыми|ими|ых|их)$/;

  // ---------- нейросеть Кодекса: какой это жанр ----------
  let net = null, tags = null;
  function setNet(model) { if (model) { net = MLP.fromJSON(model.net); tags = model.tags; } }
  function trainSet(seed = 77) {
    const rnd = U.rng(seed), byRole = r => CODEX_WORDS.filter(w => w[2] === r || (r === 'h' && w[2] === 'n')).map(w => w[0][0]);
    const F = { h: byRole('h'), g: byRole('g'), b: byRole('b'), p: ['платформы', 'облака', 'льдины', 'ступеньки', 'камни', 'листья'] };
    const ex = [], keys = Object.keys(CODEX_TRAIN);
    keys.forEach((g, y) => {
      for (const p of CODEX_TRAIN[g]) {
        const n = /\{/.test(p) ? 5 : 2;
        for (let i = 0; i < n; i++) {
          const s = p.replace(/\{(\w)\}/g, (m, k) => U.pick(F[k], rnd));
          ex.push({ text: Text.clean(s), y });
          ex.push({ text: Text.clean(Data.augment(Text.clean(s), rnd)), y });
        }
      }
    });
    return { tags: keys, examples: ex };
  }
  function genreProbs(text) {
    const t = low(text), keys = Object.keys(CODEX_GENRES), p = {};
    let nn = null;
    if (net) { nn = net.predict(Text.features(text, net.D)); }
    keys.forEach((g, i) => { p[g] = nn ? nn[tags.indexOf(g)] : 1 / keys.length; });
    let first = null, at = 1e9;
    for (const g of keys) { const m = CODEX_GENRES[g].kw.exec(t); if (m) { p[g] += CODEX_GENRES[g].w; if (m.index < at) { at = m.index; first = g; } } }
    if (first) p[first] += 0.2;
    const sum = keys.reduce((s, g) => s + p[g], 0);
    const list = keys.map(g => ({ g, p: p[g] / sum })).sort((a, b) => b.p - a.p);
    return list;
  }

  // ---------- понимание описания ----------
  function lookup(word, mem) {
    const w = low(word);
    if (STOP.has(w)) return null;
    const st = Text.stem(w);
    if (mem && mem.words && mem.words[st]) return Object.assign({ learned: true }, mem.words[st]);
    if (index.has(st)) return index.get(st);
    // «котики» → «котик»: укорачиваем только существительные, не глаголы и не прилагательные
    if (w.length >= 5 && !VERB_END.test(w) && !ADJ_END.test(w)) for (let k = 1; k <= 2 && st.length - k >= 4; k++) { const e = index.get(st.slice(0, -k)); if (e) return e; }
    return null;
  }
  function looksNoun(w) { return w.length >= 3 && !STOP.has(w) && !VERB_END.test(w) && !ADJ_END.test(w) && !/^\d+$/.test(w); }
  function understand(text, mem) {
    const t = low(text), ws = Text.words(text);
    const found = [], unknown = [];
    // слова из двух частей: «божья коровка», «воздушный шар»
    const st = ws.map(Text.stem);
    const used = new Set();
    for (const m of multi) for (let i = 0; i + m.st.length <= st.length; i++) if (m.st.every((s, k) => st[i + k] === s)) { found.push({ i, entry: m.entry, word: ws.slice(i, i + m.st.length).join(' ') }); for (let k = 0; k < m.st.length; k++) used.add(i + k); }
    ws.forEach((w, i) => {
      if (used.has(i)) return;
      if (STOP.has(w)) return;
      const e = lookup(w, mem);
      if (e && !THEME_WORDS.has(Text.stem(w))) found.push({ i, entry: e, word: w });
    });
    found.sort((a, b) => a.i - b.i);
    // роль по соседним словам
    const ctx = i => ws.slice(Math.max(0, i - 3), i).join(' ');
    const roleOf = (f) => {
      const c = ctx(f.i), prev = ws[f.i - 1] || '', next = ws.slice(f.i + 1, f.i + 3).join(' ');
      if (/(^|\s)(от|против|через|между|избега\S*|сбива\S*|уничтож\S*|объезжа\S*|бей|ударь|врагов|враги|враг)$/.test(c) || /стреля\S* (в|по)$/.test(c)) return 'b';
      if (COLLECT.test(c) || COLLECT2.test(c)) return 'g';
      if (/(^|\s)(по)$/.test(prev) && /прыга|скач|бега/.test(c)) return 'p';
      if (/(^|\s)(про|за)$/.test(prev) || /^(лов|прыга|бега|беж|лета|лети|стреля|ходит|езди|едет|мчит|собира|уворач|спаса|убега|скач|плава)/.test(ws[f.i + 1] || '')) return 'h';
      if (/^(мешают|нападают|гоняются|летят|падают на)/.test(next)) return 'b';
      return '';
    };
    const roles = { h: [], g: [], b: [], p: [] };
    for (const f of found) {
      let r = roleOf(f) || '';
      if (!r) r = f.entry.role === 'n' ? '' : f.entry.role;
      f.role = r;
    }
    // слова на месте героя/предмета, которых Амиго не знает
    ws.forEach((w, i) => {
      if (found.some(f => f.i === i) || !looksNoun(w) || THEME_WORDS.has(Text.stem(w))) return;
      const c = ctx(i), prev = ws[i - 1] || '';
      let r = '';
      if (/(^|\s)(про|за)$/.test(prev)) r = 'h';
      else if (COLLECT.test(c)) r = 'g';
      else if (/(^|\s)(от|против|через|между)$/.test(c)) r = 'b';
      if (r && !STOP.has(w)) unknown.push({ i, word: w, role: r });
    });
    for (const f of found) if (f.role) roles[f.role].push(f);
    // герой: первый подходящий, если явно не указан
    if (!roles.h.length && !unknown.some(x => x.role === 'h')) { const f = found.find(f => !f.role && (f.entry.role === 'h' || f.entry.role === 'n')); if (f) { f.role = 'h'; roles.h.push(f); } }
    for (const f of found) if (!f.role) { if (f.entry.role === 'g') roles.g.push(f); else if (f.entry.role === 'b') roles.b.push(f); }
    // мир
    let theme = null;
    for (const [id, th] of Object.entries(CODEX_THEMES)) if (th.re.test(t)) { theme = id; break; }
    // приёмы
    const features = CODEX_FEATURES.filter(f => f.re.test(t)).map(f => f.id);
    const learned = mem && mem.recipes ? mem.recipes.filter(r => r.keys.some(k => st.includes(k))) : [];
    // непонятные приёмы: «с ловушками», «и можно строить стены»
    const unknownMech = [];
    const mre = /(?:^|\s)(?:с|со|где можно|и можно|можно|чтобы можно было|и есть|умеет|может)\s+([а-яa-z]+(?:\s+[а-яa-z]+){0,2})/g;
    let mm;
    while ((mm = mre.exec(t))) {
      const phrase = mm[1].trim().split(/\s+/).filter((w, i, arr) => !(i === arr.length - 1 && STOP.has(w))).join(' '), pst = Text.words(phrase).map(Text.stem);
      const knownFeat = CODEX_FEATURES.some(f => f.re.test(phrase)), knownWord = Text.words(phrase).some(w => lookup(w, mem)), knownRec = learned.some(r => r.keys.some(k => pst.includes(k)));
      const genreWord = Object.values(CODEX_GENRES).some(g => g.kw.test(phrase));
      const filler = /^(тобой|ним|ней|ними|друзьями|мной|него|нее|нему|разными|разной|всеми|графикой|звуком|музыкой|красивой|крутой|очками|счетом|уровнями|жизнями|героем|героями)/.test(phrase);
      if (!knownFeat && !knownWord && !knownRec && !genreWord && !filler && /[а-я]{4,}/.test(phrase)) unknownMech.push(phrase);
    }
    // числа: «3 жизни», «до 100 очков», «за 30 секунд»
    const td = Text.wordsToDigits(t);
    const lives = /(\d+)\s*(жизн|сердеч)/.exec(td), goal = /до\s*(\d+)\s*очк/.exec(td), secs = /(\d+)\s*(секунд|сек(?![а-я]))/.exec(td), mins = /(\d+)\s*минут/.exec(td);
    return {
      text, genres: genreProbs(text), roles, found, unknown, theme, features, learned, unknownMech: [...new Set(unknownMech)].slice(0, 2),
      lives: lives ? U.clamp(+lives[1], 1, 9) : 0, goalScore: goal ? +goal[1] : 0,
      timeLimit: secs ? U.clamp(+secs[1], 10, 300) : mins ? U.clamp(+mins[1] * 60, 30, 600) : (/на время|таймер|за минуту/.test(t) ? 60 : 0),
      speed: /быстр|скоростн|бешен/.test(t) ? 1.25 : /медлен|спокойн|для малыш|легк/.test(t) ? 0.8 : 1,
      hard: /сложн|трудн|хардкор/.test(t), easy: /легк|прост|для малыш/.test(t),
    };
  }

  // ---------- сборка чертежа игры ----------
  const S = s => ({ tag: s[0], every: s[1], from: s[2], max: s[3] || 0, startAfter: s[4] || 0, scale: s[5] !== false });
  function genreRecipe(g, items, level) {
    const hi = level !== 'medium';
    const R = { things: {}, spawns: [], touch: [], abilities: [], events: [], world: { gravity: 1, wrap: false, jumps: 1 }, levelEvery: 15, bossMode: 'survive', bossOk: true };
    const T = (tag, o) => { R.things[tag] = Object.assign({ emoji: items[tag] ? items[tag].emoji : '', name: items[tag] ? items[tag].name : '', role: /bad|boss|eshot/.test(tag) ? 'bad' : /good/.test(tag) ? 'good' : 'neutral' }, o); };
    const hitBad = ['bad', 'bad2', 'boss', 'eshot'];
    const goodTouch = (n) => ['score:' + n, 'remove_b', 'burst', 'sound:collect'];
    const badTouch = ['damage:1', 'remove_b', 'burst:bad', 'shake'];
    if (g === 'catch') {
      T('good', { move: 'fall', speed: 1 }); T('bad', { move: 'fall', speed: 1 }); T('good2', { move: 'fall', speed: 1.45, size: 0.85, points: 3 }); T('bad2', { move: 'zigzag', speed: 1.1 });
      R.spawns = [S(['good', 0.85, 'top']), S(['bad', 2.1, 'top', 0, 4])];
      if (hi) R.spawns.push(S(['good2', 7, 'top', 0, 8]), S(['bad2', 5.5, 'top', 0, 20]));
      R.touch = [{ a: 'hero', b: 'good', do: goodTouch(1) }, { a: 'hero', b: 'good2', do: goodTouch(3) }, { a: 'hero', b: hitBad, do: badTouch }];
      R.levelEvery = 15;
    } else if (g === 'dodge') {
      T('good', { move: 'still', life: 6, size: 0.9 }); T('bad', { move: 'aim', speed: 1.05 }); T('bad2', { move: 'chase', speed: 0.5, life: 8 }); T('good2', { move: 'still', life: 4, size: 0.8, points: 5 });
      R.spawns = [S(['bad', 0.75, 'edges']), S(['good', 2.4, 'random', 3])];
      if (hi) R.spawns.push(S(['bad2', 7, 'edges', 2, 15]), S(['good2', 9, 'random', 1, 10]));
      R.touch = [{ a: 'hero', b: 'good', do: goodTouch(5) }, { a: 'hero', b: 'good2', do: goodTouch(10) }, { a: 'hero', b: hitBad, do: badTouch }];
      R.events = [{ every: 1, do: ['score:1'] }];
      R.levelEvery = 30;
    } else if (g === 'shooter') {
      T('bad', { move: 'fall', speed: 0.55, hp: 1, points: 1 }); T('bad2', { move: 'zigzag', speed: 0.7, hp: 2, points: 3 }); T('good', { move: 'fall', speed: 1, size: 0.9 });
      T('shot', { emoji: '', move: 'rise', speed: 4.2, size: 0.32 }); T('eshot', { emoji: '', move: 'aim', speed: 1.5, size: 0.35 });
      R.spawns = [S(['bad', 1.05, 'top']), S(['good', 7, 'top', 2, 6])];
      if (hi) R.spawns.push(S(['bad2', 4.5, 'top', 0, 15]));
      R.abilities = [{ button: 'action', do: 'shoot', spawn: 'shot', cooldown: 0.3, auto: true }];
      R.touch = [{ a: 'shot', b: ['bad', 'bad2', 'boss'], do: ['hit_b:1', 'remove_a', 'sound:pop'] }, { a: 'hero', b: 'good', do: goodTouch(3) }, { a: 'hero', b: hitBad, do: badTouch }];
      R.levelEvery = 20; R.bossMode = 'fight';
    } else if (g === 'runner') {
      T('bad', { move: 'left', speed: 1.6 }); T('bad2', { move: 'left', speed: 1.85, size: 0.9 }); T('good', { move: 'left', speed: 1.6, size: 0.8 });
      R.spawns = [S(['bad', 1.55, 'ground']), S(['good', 1.2, 'air'])];
      if (hi) R.spawns.push(S(['bad2', 6.5, 'air', 0, 15]));
      R.touch = [{ a: 'hero', b: 'good', do: goodTouch(2) }, { a: 'hero', b: hitBad, do: badTouch }];
      R.events = [{ every: 0.5, do: ['score:1'] }];
      R.levelEvery = 50; R.bossOk = false;
    } else if (g === 'flappy') {
      T('bad', { move: 'left', speed: 1.35, size: 1 }); T('good', { move: 'left', speed: 1.35, size: 0.8 });
      R.spawns = [{ tag: 'bad', every: 1.75, from: 'column', gap: 150, withGood: 'good', scale: true }];
      R.touch = [{ a: 'hero', b: 'gate', do: ['score:1', 'remove_b', 'sound:collect'] }, { a: 'hero', b: 'good', do: goodTouch(2) }, { a: 'hero', b: hitBad, do: ['damage:1', 'shake'] }];
      R.levelEvery = 10; R.bossOk = false;
    } else if (g === 'topdown') {
      T('good', { move: 'still', size: 0.85 }); T('bad', { move: 'wander', speed: 0.75 }); T('bad2', { move: 'chase', speed: 0.42 });
      R.spawns = hi ? [S(['bad2', 14, 'edges', 2, 20])] : [];
      R.touch = [{ a: 'hero', b: 'good', do: goodTouch(1) }, { a: 'hero', b: hitBad, do: ['damage:1', 'teleport_a', 'shake'] }];
      R.levelEvery = 0;
    } else if (g === 'jumper') {
      T('good', { move: 'still', size: 0.85 }); T('bad', { move: 'wander', speed: 0.5 }); T('platform', { emoji: items.platform ? items.platform.emoji : '', name: items.platform ? items.platform.name : 'платформа' });
      R.touch = [{ a: 'hero', b: 'good', do: goodTouch(5) }, { a: 'hero', b: hitBad, do: badTouch }];
      R.levelEvery = 60; R.bossOk = false;
    } else if (g === 'tapper') {
      T('good', { move: 'rise', speed: 0.35, life: 2.2, size: 1.3 }); T('bad', { move: 'still', life: 2, size: 1.25 }); T('good2', { move: 'rise', speed: 0.6, life: 1.4, size: 1, points: 5 });
      R.spawns = [S(['good', 0.6, 'random', 6]), S(['bad', 2.2, 'random', 3, 4])];
      if (hi) R.spawns.push(S(['good2', 6, 'random', 1, 8]));
      R.touch = [{ a: 'tap', b: 'good', do: goodTouch(1) }, { a: 'tap', b: 'good2', do: goodTouch(5) }, { a: 'tap', b: ['bad', 'bad2'], do: ['damage:1', 'remove_b', 'burst:bad', 'shake'] }];
      R.levelEvery = 25; R.bossOk = false; R.timeLimit = 60;
    } else if (g === 'racer') {
      T('bad', { move: 'fall', speed: 2, rot: 1 }); T('good', { move: 'fall', speed: 2, size: 0.8 }); T('bad2', { move: 'fall', speed: 2.6, rot: 1 });
      R.spawns = [S(['bad', 0.95, 'lane']), S(['good', 1.5, 'lane'])];
      if (hi) R.spawns.push(S(['bad2', 5, 'lane', 0, 15]));
      R.touch = [{ a: 'hero', b: 'good', do: goodTouch(2) }, { a: 'hero', b: hitBad, do: badTouch }];
      R.events = [{ every: 0.5, do: ['score:1'] }];
      R.levelEvery = 50; R.bossOk = false;
    }
    return R;
  }
  function pickGenre(u, forced) {
    if (forced && CODEX_GENRES[forced]) return forced;
    return u.genres[0].g;
  }
  function itemFrom(f) { return f ? { emoji: f.entry.emoji, name: f.entry.name, word: f.word } : null; }
  function hashStr(s) { let h = 2166136261; for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); } return (h >>> 0).toString(36); }
  function capital(s) { return s ? s[0].toUpperCase() + s.slice(1) : s; }
  function title(g, hero, theme) {
    const G = CODEX_GENRES[g];
    if (hero && hero.name && hero.name !== 'амиго') return capital(hero.name) + '-' + G.suffix;
    if (hero && hero.amigo) return 'Амиго-' + G.suffix;
    return capital(G.name) + (theme ? ': ' + CODEX_THEMES[theme].name : '');
  }
  // u — понимание описания, level — medium/high/ultra
  function design(u, level = 'high', opt = {}) {
    const g = pickGenre(u, opt.genre), G = CODEX_GENRES[g], L = CODEX_LEVELS[level] || CODEX_LEVELS.high;
    const hf = u.roles.h[0], gf = u.roles.g, bf = u.roles.b, pf = u.roles.p[0];
    const def = e => e === 'amigo' ? { emoji: '🙂', name: 'амиго', amigo: true } : e ? { emoji: e, name: '' } : null;
    let hero = itemFrom(hf) || def(G.hero) || def('amigo');
    if (hero.name === 'амиго') hero = { emoji: '🙂', name: 'амиго', amigo: true };
    // враг не назван — берём того, кто подходит к миру (пингвину — снеговик, а не пришелец)
    const guess = u.theme || themeFromItems([hero, itemFrom(gf[0])]);
    const themedBad = !bf.length && guess && THEME_BAD_GENRES.includes(g) && THEME_BAD[guess] ? { emoji: THEME_BAD[guess], name: '' } : null;
    const items = {
      good: itemFrom(gf[0]) || def(G.good), bad: itemFrom(bf[0]) || themedBad || def(G.bad),
      good2: itemFrom(gf[1]) || null, bad2: itemFrom(bf[1]) || null, platform: itemFrom(pf),
    };
    // второй хороший и плохой предмет — свои варианты
    if (!items.good2 && items.good) items.good2 = { emoji: { '🪙': '💎', '⭐': '🌟', '🐟': '🐠', '🍎': '🍏', '🎈': '🎁' }[items.good.emoji] || '💎', name: 'редкий приз' };
    if (!items.bad2 && items.bad) items.bad2 = { emoji: { '💣': '🔥', '☄️': '🪨', '👾': '👽', '🌵': '🦅', '🚙': '🚚', '👻': '💀', '🦈': '🐙', '⛄': '🧊', '🦂': '🐍', '🦇': '🕷️', '🐺': '🐻', '🦷': '🍋', '🐝': '🦟' }[items.bad.emoji] || items.bad.emoji, name: items.bad.name };
    if (g === 'flappy' && !bf.length) items.bad = { emoji: '', name: 'трубы', pipe: true };
    const R = genreRecipe(g, items, level);
    const theme = u.theme || themeFromItems([hero, items.good, items.bad]) || { shooter: 'space', flappy: 'sky', runner: g === 'runner' && hero.emoji === '🦖' ? 'desert' : 'farm', racer: 'city', dodge: 'space', topdown: 'castle', jumper: 'sky', catch: 'sky', tapper: 'candy' }[g] || 'sky';
    const notes = [];
    const spec = {
      v: 1, genre: g, level, control: G.control, icon: G.icon, request: u.text,
      theme: Object.assign({ id: theme }, CODEX_THEMES[theme]),
      hero: { emoji: hero.emoji, name: hero.name, amigo: !!hero.amigo, size: 1.15 },
      things: R.things, spawns: R.spawns, touch: R.touch, abilities: R.abilities, events: R.events, world: R.world,
      lives: u.lives || (u.hard ? 2 : u.easy ? 5 : 3), timeLimit: u.timeLimit || R.timeLimit || 0,
      levelEvery: R.levelEvery, goal: { level: 0 }, boss: { on: false, every: 3, mode: R.bossMode, emoji: '', hp: 12 },
      powers: [], powerEvery: 0, fx: Object.assign({}, L.fx), pace: +((G.pace || 1) * (u.hard ? 1.2 : u.easy ? 0.8 : 1) * (u.speed || 1)).toFixed(2), ramp: level === 'medium' ? 150 : 120,
      learned: [], notes,
    };
    delete spec.theme.re;
    if (items.bad && items.bad.pipe) spec.things.bad.pipe = true;
    if (spec.control === 'tap') spec.hero = { emoji: '', name: '', size: 1 };
    // приёмы из описания и из уровня Кодекса
    const want = new Set(u.features);
    if (level !== 'medium') { want.add('powers'); if (R.levelEvery || g === 'topdown') want.add('levels'); if (R.bossOk) want.add('boss'); }
    if (level === 'ultra') { if (R.bossOk) want.add('boss'); spec.goal.level = R.bossOk ? 6 : 0; }
    applyFeatures(spec, [...want], notes);
    if (u.goalScore) spec.events.push({ at_score: u.goalScore, do: ['win:Ты набрал ' + u.goalScore + ' очков! 🏆'] });
    for (const r of u.learned || []) applyRecipe(spec, r, notes);
    spec.title = title(g, spec.control === 'tap' ? null : hero, u.theme);
    spec.help = G.help.replace('{good}', (items.good && items.good.emoji) || 'призы').replace('{bad}', (items.bad && (items.bad.emoji || items.bad.name)) || 'врагов');
    spec.id = 'c' + hashStr(JSON.stringify([spec.genre, spec.hero.emoji, items.good && items.good.emoji, items.bad && items.bad.emoji, theme, level, u.text]));
    return spec;
  }
  const THEME_BAD = { space: '👾', water: '🦈', forest: '🐺', desert: '🦂', winter: '⛄', night: '🦇', castle: '👻', lava: '🔥', candy: '🦷', farm: '🐝', sky: '⚡' };
  const THEME_BAD_GENRES = ['catch', 'shooter', 'jumper', 'topdown', 'dodge'];
  const ITEM_THEMES = [[/🐟|🐠|🦈|🐙|🐬|🐳|🦀|🪼|🐚|🦭|🧜/, 'water'], [/🚀|👾|🛸|☄️|🧑‍🚀|👽/, 'space'], [/🚗|🚚|🚌|🚕|🏍️|🚲|👮|🦹/, 'city'], [/🦖|🌵|🐫|🦂/, 'desert'],
    [/🐧|❄️|⛄|🧊|🎅|🦭/, 'winter'], [/👻|🧟|🧛|💀|🦇|🎃|🧙‍♀️/, 'night'], [/🐉|🤺|👸|🤴|🧙|🧌|👑/, 'castle'], [/🐝|🌸|🍯|🦋|🐞|🐮|🐷|🐔|🐑|🐐|🥕|🍎/, 'farm'],
    [/🍬|🍫|🧁|🍰|🍩|🍦|🍪/, 'candy'], [/🦊|🐻|🐺|🦔|🐿️|🦌|🍄|🌰|🐸|🐍/, 'forest'], [/🔥|🌋/, 'lava']];
  function themeFromItems(list) {
    for (const it of list) if (it && it.emoji) for (const [re, id] of ITEM_THEMES) if (re.test(it.emoji)) return id;
    return null;
  }
  function applyFeatures(spec, list, notes) {
    const add = n => { if (!notes.includes(n)) notes.push(n); };
    for (const f of list) {
      if (f === 'powers' || f === 'shield' || f === 'magnet' || f === 'slow' || f === 'double' || f === 'hearts' || f === 'bombs') {
        const base = spec.control === 'tap' ? ['double', 'slow', 'heart'] : ['shield', 'magnet', 'slow', 'double', 'heart'];
        const p = new Set(spec.powers);
        if (f === 'powers') base.forEach(x => p.add(x)); else p.add(f === 'hearts' ? 'heart' : f === 'bombs' ? 'bomb' : f);
        if (spec.control === 'tap') p.delete('magnet'), p.delete('shield');
        spec.powers = [...p]; spec.powerEvery = spec.powerEvery || 13; add('бонусы ' + spec.powers.map(x => CodexEngine.POWER[x].emoji).join(''));
      } else if (f === 'levels') { if (!spec.levelEvery && spec.genre !== 'topdown') spec.levelEvery = 20; add('уровни'); }
      else if (f === 'boss') {
        if (['runner', 'flappy', 'jumper', 'tapper', 'racer'].includes(spec.genre)) continue;
        spec.boss.on = true; spec.boss.emoji = spec.boss.emoji || bossEmoji(spec); if (!spec.levelEvery && spec.genre !== 'topdown') spec.levelEvery = 20; add('босс');
        if (spec.boss.mode === 'fight' && !spec.things.eshot) spec.things.eshot = { emoji: '', move: 'aim', speed: 1.5, size: 0.35, role: 'bad' };
      } else if (f === 'timer') { spec.timeLimit = spec.timeLimit || 60; add('игра на время'); }
      else if (f === 'portal') {
        spec.things.portal = { emoji: '🌀', name: 'портал', move: 'still', life: 9, size: 1.1, role: 'neutral' };
        spec.spawns.push({ tag: 'portal', every: 8, from: 'random', max: 2, scale: false });
        spec.touch.push({ a: 'hero', b: 'portal', do: ['teleport_a', 'remove_b', 'sound:power', 'shield:1'] });
        add('порталы 🌀');
      } else if (f === 'shoot' && !spec.abilities.some(a => a.do === 'shoot')) {
        if (spec.control === 'tap') continue;
        spec.things.shot = spec.things.shot || { emoji: '', move: 'rise', speed: 4.2, size: 0.32 };
        spec.abilities.push({ button: spec.control === 'runner' || spec.control === 'flappy' ? 'down' : 'action', do: 'shoot', spawn: 'shot', cooldown: 0.4, auto: spec.control === 'horizontal', label: '🔫' });
        spec.touch.unshift({ a: 'shot', b: ['bad', 'bad2', 'boss'], do: ['hit_b:1', 'remove_a', 'sound:pop'] });
        add('стрельба');
      } else if (f === 'djump') { spec.world.jumps = 2; add('двойной прыжок'); }
      else if (f === 'gravity') { if (spec.control === 'runner' || spec.control === 'flappy') { spec.world.gravity = -1; add('гравитация наоборот'); } }
      else if (f === 'wrap') { spec.world.wrap = true; add('проход сквозь стены'); }
      else if (f === 'chasers') { if (spec.things.bad2) { spec.things.bad2.move = 'chase'; add('преследователи'); } }
    }
  }
  function bossEmoji(spec) {
    const b = spec.things.bad && spec.things.bad.emoji;
    return { '👾': '👽', '👻': '🎃', '☄️': '🌑', '💣': '🤖', '🦈': '🐋', '🧟': '🧟‍♂️', '🐺': '🐺' }[b] || b || '👹';
  }
  // ---------- выученные приёмы (рецепты) ----------
  const RECIPE_TAG = /^[a-z][a-z0-9_]{0,15}$/, BASE_TAGS = ['hero', 'good', 'bad', 'good2', 'bad2', 'shot', 'eshot', 'boss', 'power', 'platform', 'tap', 'gate', 'portal'];
  const isEmoji = s => typeof s === 'string' && s.length <= 12 && /\p{Extended_Pictographic}/u.test(s);
  function validateRecipe(r) {
    const errs = [], out = { name: String(r && r.name || '').slice(0, 40), explain: String(r && r.explain || '').slice(0, 400), rules: [] };
    if (!r || r.possible === false) return { ok: false, errs: ['невозможно'], recipe: out };
    const rules = Array.isArray(r.rules) ? r.rules.slice(0, 10) : [];
    const own = new Set(rules.filter(x => x && x.type === 'thing' && RECIPE_TAG.test(x.tag) && !BASE_TAGS.includes(x.tag)).map(x => x.tag));
    const tagOk = t => (Array.isArray(t) ? t : [t]).every(x => typeof x === 'string' && (BASE_TAGS.includes(x) || own.has(x)));
    const num = (v, a, b, d) => { const n = Number(v); return isFinite(n) ? U.clamp(n, a, b) : d; };
    const effOk = list => Array.isArray(list) && list.length && list.length <= 8 && list.every(e => typeof e === 'string' && CodexEngine.EFFECTS.includes(e.split(':')[0]) && e.length <= 40);
    for (const x of rules) {
      if (!x || typeof x !== 'object') continue;
      if (x.type === 'thing') {
        if (!own.has(x.tag) || !isEmoji(x.emoji)) { errs.push('thing'); continue; }
        out.rules.push({ type: 'thing', tag: x.tag, emoji: x.emoji, name: String(x.name || '').slice(0, 30), move: CodexEngine.MOVES.includes(x.move) ? x.move : 'still',
          speed: num(x.speed, 0.2, 4, 1), size: num(x.size, 0.3, 3, 1), life: num(x.life, 0, 30, 0), hp: Math.round(num(x.hp, 1, 50, 1)), points: Math.round(num(x.points, 0, 100, 1)),
          role: ['good', 'bad', 'neutral'].includes(x.role) ? x.role : 'neutral' });
      } else if (x.type === 'spawn') {
        if (!tagOk(x.tag) || BASE_TAGS.includes(x.tag) && x.tag !== 'good' && x.tag !== 'bad') { errs.push('spawn'); continue; }
        out.rules.push({ type: 'spawn', tag: x.tag, every: num(x.every, 0.3, 60, 3), from: CodexEngine.FROMS.includes(x.from) && x.from !== 'column' ? x.from : 'random', max: Math.round(num(x.max, 0, 30, 0)), startAfter: num(x.startAfter, 0, 120, 0), scale: x.scale !== false });
      } else if (x.type === 'touch') {
        if (!tagOk(x.a) || !tagOk(x.b) || !effOk(x.do)) { errs.push('touch'); continue; }
        out.rules.push({ type: 'touch', a: x.a, b: x.b, do: x.do.slice(0, 8) });
      } else if (x.type === 'ability') {
        if (!['shoot', 'place', 'dash', 'bomb', 'shield', 'jump'].includes(x.do) || (x.spawn && !tagOk(x.spawn))) { errs.push('ability'); continue; }
        out.rules.push({ type: 'ability', do: x.do, spawn: x.spawn || '', cooldown: num(x.cooldown, 0.1, 30, 1), label: isEmoji(x.label) ? x.label : '⚡' });
      } else if (x.type === 'event') {
        if (!effOk(x.do)) { errs.push('event'); continue; }
        const ev = { type: 'event', do: x.do.slice(0, 8) };
        if (x.every != null) ev.every = num(x.every, 0.5, 120, 5); else if (x.at_score != null) ev.at_score = Math.round(num(x.at_score, 1, 100000, 10)); else if (x.at_time != null) ev.at_time = num(x.at_time, 1, 600, 30); else { errs.push('event'); continue; }
        out.rules.push(ev);
      } else if (x.type === 'world') {
        out.rules.push({ type: 'world', gravity: x.gravity === -1 ? -1 : 1, wrap: !!x.wrap });
      }
    }
    return { ok: out.rules.length > 0, errs, recipe: out };
  }
  function applyRecipe(spec, r, notes) {
    for (const x of r.rules) {
      if (x.type === 'thing') spec.things[x.tag] = { emoji: x.emoji, name: x.name, move: x.move, speed: x.speed, size: x.size, life: x.life, hp: x.hp, points: x.points, role: x.role };
      else if (x.type === 'spawn') spec.spawns.push({ tag: x.tag, every: x.every, from: x.from, max: x.max, startAfter: x.startAfter, scale: x.scale });
      else if (x.type === 'touch') spec.touch.push({ a: x.a, b: x.b, do: x.do });
      else if (x.type === 'ability') {
        const busy = spec.abilities.some(a => a.button === 'action') || spec.control === 'runner' || spec.control === 'flappy' || spec.control === 'tap';
        spec.abilities.push({ button: busy ? 'second' : 'action', do: x.do, spawn: x.spawn, cooldown: x.cooldown, label: x.label, noTap: busy });
      } else if (x.type === 'event') { const e = Object.assign({}, x); delete e.type; spec.events.push(e); }
      else if (x.type === 'world') { if (x.gravity === -1 && (spec.control === 'runner' || spec.control === 'flappy')) spec.world.gravity = -1; if (x.wrap) spec.world.wrap = true; }
    }
    if (!spec.learned.includes(r.name)) spec.learned.push(r.name);
    if (notes && !notes.includes(r.name)) notes.push(r.name + ' (выучил сам)');
  }

  // ---------- правки словами: «сделай быстрее», «добавь босса», «вместо кота собака» ----------
  function edit(spec, text, mem) {
    const t = low(text), s = JSON.parse(JSON.stringify(spec)), changes = [];
    const td = Text.wordsToDigits(t);
    if (/быстрее|побыстрее|ускор/.test(t)) { s.pace = +(s.pace * 1.25).toFixed(2); changes.push('игра быстрее'); }
    if (/медленнее|помедленнее|замедли/.test(t)) { s.pace = +(s.pace * 0.8).toFixed(2); changes.push('игра медленнее'); }
    if (/сложнее|потруднее|хардкор/.test(t)) { s.pace = +(s.pace * 1.2).toFixed(2); s.lives = Math.max(1, s.lives - 1); changes.push('сложнее'); }
    if (/легче|проще|полегче/.test(t)) { s.pace = +(s.pace * 0.8).toFixed(2); s.lives = Math.min(9, s.lives + 1); changes.push('легче'); }
    const lv = /(\d+)\s*(жизн|сердеч)/.exec(td);
    if (lv) { s.lives = U.clamp(+lv[1], 1, 9); changes.push('жизней: ' + s.lives); } else if (/одна жизнь|одну жизнь|без жизней/.test(t)) { s.lives = 1; changes.push('одна жизнь'); }
    else if (/больше жизней/.test(t)) { s.lives = Math.min(9, s.lives + 2); changes.push('жизней: ' + s.lives); }
    const bad = s.spawns.filter(x => /bad/.test(x.tag)), good = s.spawns.filter(x => /good/.test(x.tag));
    if (/больше (врагов|препятств|монстр|бомб)/.test(t)) { bad.forEach(x => { x.every = +(x.every * 0.7).toFixed(2); }); changes.push('больше врагов'); }
    if (/меньше (врагов|препятств|монстр|бомб)/.test(t)) { bad.forEach(x => { x.every = +(x.every * 1.45).toFixed(2); }); changes.push('меньше врагов'); }
    if (/больше (бонус|приз|монет|звезд|еды|предмет)/.test(t)) { good.forEach(x => { x.every = +(x.every * 0.75).toFixed(2); }); changes.push('больше призов'); }
    const notes = s.notes || (s.notes = []);
    const feat = CODEX_FEATURES.filter(f => f.re.test(t)).map(f => f.id);
    if (/убер\S* босс|без босс/.test(t)) { s.boss.on = false; changes.push('без босса'); }
    else if (feat.includes('boss')) { applyFeatures(s, ['boss'], notes); changes.push(s.boss.on ? 'добавил босса' : 'в этом жанре босса не бывает'); }
    for (const f of feat.filter(f => f !== 'boss')) { const before = JSON.stringify(s); applyFeatures(s, [f], notes); if (JSON.stringify(s) !== before) changes.push('добавил: ' + CODEX_FEATURES.find(x => x.id === f).name); }
    if (/без звук|выключи звук/.test(t)) { s.fx.sound = false; changes.push('без звука'); }
    if (/со звуком|включи звук/.test(t)) { s.fx.sound = true; changes.push('со звуком'); }
    if (/красивее|эффект|покруче/.test(t)) { s.fx = Object.assign({}, CODEX_LEVELS.high.fx); changes.push('больше эффектов'); }
    // мир
    for (const [id, th] of Object.entries(CODEX_THEMES)) if (th.re.test(t) && /(фон|мир|пусть|в |на |поменяй|сделай)/.test(t) && id !== s.theme.id) { s.theme = Object.assign({ id }, th); delete s.theme.re; changes.push('мир: ' + th.name); break; }
    // замены: «вместо X Y», «герой — X», «пусть враги будут X», «лови X»
    const u = understand(text, mem);
    const ent = f => ({ emoji: f.entry.emoji, name: f.entry.name });
    const m = /вместо\s+(\S+)\s+(?:пусть\s+будет\s+|будет\s+|сделай\s+)?(\S+)/.exec(t) || /(\S+)\s+вместо\s+(\S+)/.exec(t);
    if (m) {
      const a = /вместо\s+(\S+)/.exec(t)[1], bw = m[1] === a ? m[2] : m[1];
      const from = lookup(a, mem), to = lookup(bw, mem);
      if (to) {
        let done = false;
        if (from && s.hero.emoji === from.emoji) { s.hero.emoji = to.emoji; s.hero.name = to.name; s.hero.amigo = false; done = true; }
        for (const k of Object.keys(s.things)) if (from && s.things[k].emoji === from.emoji) { s.things[k].emoji = to.emoji; s.things[k].name = to.name; done = true; }
        if (done) changes.push(`${to.emoji} вместо ${from.emoji}`);
      }
    }
    if (/(геро\S*|играть за|будет)\s/.test(t) && u.roles.h[0] && !m) { const h = ent(u.roles.h[0]); if (h.emoji !== s.hero.emoji && s.control !== 'tap') { s.hero.emoji = h.emoji; s.hero.name = h.name; s.hero.amigo = false; changes.push('герой ' + h.emoji); } }
    if (/враг|препятств|мешают|от\s/.test(t) && u.roles.b[0] && !m && s.things.bad) { const b = ent(u.roles.b[0]); if (b.emoji !== s.things.bad.emoji) { s.things.bad.emoji = b.emoji; s.things.bad.name = b.name; s.things.bad.pipe = false; changes.push('враги ' + b.emoji); } }
    if (/(лов|собира|приз|еда)/.test(t) && u.roles.g[0] && !m && s.things.good) { const g = ent(u.roles.g[0]); if (g.emoji !== s.things.good.emoji) { s.things.good.emoji = g.emoji; s.things.good.name = g.name; changes.push('собираем ' + g.emoji); } }
    for (const r of u.learned || []) if (!s.learned.includes(r.name)) { applyRecipe(s, r, notes); changes.push('приём «' + r.name + '»'); }
    const nm = /(?:назови|переименуй)(?:\s+игру)?(?:\s+в)?\s+[«"]?([^«»"]{2,40})[»"]?$/.exec(t);
    if (nm) { s.title = capital(text.trim().replace(/^.*?(?:назови|переименуй)(?:\s+игру)?(?:\s+в)?\s+/i, '').replace(/[«»"]/g, '').slice(0, 40)); changes.push('название «' + s.title + '»'); }
    if (changes.length) { s.version = (s.version || 1) + 1; }
    return { spec: s, changes, unknownMech: changes.length ? [] : u.unknownMech, understood: u };
  }

  // ---------- вопросы супер-мозгу «как это сделать» (только в режиме Ультра) ----------
  const DSL_HELP = 'Блоки моего движка (JSON):\n' +
    '- {"type":"thing","tag":"имя_латиницей","emoji":"🪤","name":"ловушка","role":"good|bad|neutral","move":"' + CodexEngine.MOVES.join('|') + '","speed":1,"size":1,"life":0,"hp":1,"points":1}\n' +
    '- {"type":"spawn","tag":"…","every":секунды,"from":"top|bottom|left|right|edges|random|ground|air|lane|hero","max":0,"startAfter":0}\n' +
    '- {"type":"touch","a":"hero|tap|тег","b":"тег или [теги]","do":["эффект",…]} — что происходит, когда a касается b\n' +
    '- {"type":"ability","do":"shoot|place|dash|bomb|shield","spawn":"тег","cooldown":секунды,"label":"эмодзи кнопки"} — кнопка игрока\n' +
    '- {"type":"event","every":секунды или "at_score":N или "at_time":секунды,"do":[эффекты]}\n' +
    '- {"type":"world","gravity":1 или -1,"wrap":true|false}\n' +
    'Готовые теги: hero (игрок), good, good2 (призы), bad, bad2 (враги), shot (пуля игрока), boss, platform.\n' +
    'Эффекты: score:N, damage:N, heal:N, remove_a, remove_b, hit_b:N, shield:сек, slow:сек, fast:сек, magnet:сек, double:сек, freeze:сек, grow:сек, shrink:сек, clear:тег, teleport_a, teleport_b, spawn:тег, bounce_a, level_up, win, burst, shake, sound:collect|hit|power|pop, text:надпись.';
  function mechPrompt(phrase, spec) {
    return 'Я — Амиго, маленькая нейросеть. Я сам программирую игры в своём движке. Объясни мне, КАК сделать в игре «' + phrase + '», чтобы я понял и дальше делал это сам.\n' +
      'Сейчас игра: жанр «' + CODEX_GENRES[spec.genre].name + '», герой ' + (spec.hero.emoji || 'нет') + ', призы ' + (spec.things.good ? spec.things.good.emoji : '-') + ', враги ' + (spec.things.bad ? spec.things.bad.emoji || 'трубы' : '-') + '.\n' +
      DSL_HELP + '\n\nОтветь ТОЛЬКО JSON без пояснений вокруг: {"possible":true,"name":"короткое название приёма по-русски","explain":"1–2 простых предложения для ребёнка, как это работает","rules":[…не больше 6 блоков…]}.\n' +
      'Если этого нельзя сделать такими блоками, ответь {"possible":false,"explain":"почему"}. Не пиши код на JavaScript — только блоки.';
  }
  function wordsPrompt(list) {
    return 'Я — Амиго, маленькая нейросеть. Я рисую предметы в играх одним эмодзи. Подскажи, как нарисовать эти слова, чтобы я запомнил: ' + list.map(w => '«' + w.word + '»').join(', ') + '.\n' +
      'Ответь ТОЛЬКО JSON-массивом: [{"word":"слово как в списке","name":"слово в начальной форме","emoji":"один эмодзи","role":"hero|good|bad"}]. Роль: hero — может быть героем, good — приз, bad — враг или препятствие.';
  }
  function parseJSON(text) {
    const t = String(text || '');
    const m = /```(?:json)?\s*([\s\S]*?)```/.exec(t);
    const body = m ? m[1] : t;
    const a = body.search(/[[{]/), b = Math.max(body.lastIndexOf('}'), body.lastIndexOf(']'));
    if (a < 0 || b < a) return null;
    try { return JSON.parse(body.slice(a, b + 1)); } catch (e) { return null; }
  }
  function learnWords(mem, list) {
    const got = [];
    for (const x of Array.isArray(list) ? list : []) {
      if (!x || typeof x.word !== 'string' || !isEmoji(x.emoji)) continue;
      const st = Text.stem(Text.clean(x.word).split(' ')[0] || '');
      if (!st) continue;
      const role = { hero: 'h', good: 'g', bad: 'b' }[x.role] || 'n';
      mem.words[st] = { name: String(x.name || x.word).slice(0, 30).toLowerCase(), emoji: x.emoji, role };
      const st2 = Text.stem(Text.clean(x.name || '').split(' ')[0] || ''); if (st2 && st2 !== st) mem.words[st2] = mem.words[st];
      got.push(mem.words[st]);
    }
    return got;
  }
  function learnRecipe(mem, phrase, recipe) {
    const keys = Text.words(phrase).filter(w => !STOP.has(w) && w.length > 2).map(Text.stem);
    const r = Object.assign({ keys: [...new Set(keys)] }, recipe);
    mem.recipes = mem.recipes.filter(x => x.name !== r.name);
    mem.recipes.push(r);
    return r;
  }
  function describe(spec) {
    const th = spec.things, G = CODEX_GENRES[spec.genre];
    const parts = [`жанр: ${G.name}`];
    if (spec.hero && spec.hero.emoji) parts.push('герой ' + (spec.hero.amigo ? 'Амиго' : spec.hero.emoji));
    if (th.good && th.good.emoji) parts.push((spec.control === 'tap' ? 'жмём на ' : 'собираем ') + th.good.emoji);
    if (th.bad) parts.push((spec.genre === 'flappy' ? 'препятствия ' : 'враги ') + (th.bad.emoji || 'трубы'));
    parts.push('мир: ' + spec.theme.name);
    return parts.join(' · ');
  }
  // ---------- режим Ультра: варианты игры и подбор сложности роботом-игроком ----------
  function variants(spec) {
    const out = [{ name: 'основной', spec }];
    const b = JSON.parse(JSON.stringify(spec));
    if (b.things.bad2) { b.things.bad2.move = spec.control === 'horizontal' || spec.control === 'lanes' ? 'zigzag' : 'chase'; b.spawns.forEach(x => { if (x.tag === 'bad2') x.every = +(x.every * 0.8).toFixed(2); }); }
    b.powerEvery = Math.max(9, (b.powerEvery || 13) - 3);
    out.push({ name: 'хитрые враги и больше бонусов', spec: b });
    const c = JSON.parse(JSON.stringify(spec));
    c.spawns.forEach(x => { if (/good/.test(x.tag)) x.every = +(x.every * 0.8).toFixed(2); if (/bad/.test(x.tag)) x.every = +(x.every * 0.9).toFixed(2); });
    c.ramp = Math.round((c.ramp || 120) * 0.8);
    out.push({ name: 'больше всего и быстрее растёт сложность', spec: c });
    return out;
  }
  // оценка: интересно, когда робот держится 70–110 секунд и проходит несколько уровней
  function rate(res, spec) {
    if (spec.timeLimit) { const ratio = res.runs.reduce((s, r) => s + r.caught / Math.max(1, r.caught + r.missed), 0) / res.runs.length; return -Math.abs(ratio - 0.72) * 100 + res.level; }
    const target = 90, t = res.time;
    return -Math.abs(t - target) / 2 + res.level * 2 + (res.wins ? 3 : 0) - (t >= 150 ? 15 : 0);
  }
  async function tune(spec, onIter, opt = {}) {
    let lo = 0.45, hi = 2, best = null;
    const tick = opt.tick || (() => null);
    const metric = r => spec.timeLimit ? r.runs.reduce((s, x) => s + x.caught / Math.max(1, x.caught + x.missed), 0) / r.runs.length : r.time;
    const good = spec.timeLimit ? m => m >= 0.62 && m <= 0.82 : m => m >= 70 && m <= 110;
    let pace = spec.pace || 1;
    for (let i = 0; i < (opt.iters || 6); i++) {
      const s = Object.assign({}, spec, { pace: +pace.toFixed(2) });
      const res = playtestSpec(s, opt.seconds || 150);
      const m = metric(res);
      if (!best || Math.abs((spec.timeLimit ? 0.72 : 90) - m) < Math.abs((spec.timeLimit ? 0.72 : 90) - best.m)) best = { pace: s.pace, res, m };
      if (onIter) onIter({ i, pace: s.pace, res, m });
      await tick();
      if (good(m)) break;
      const tooEasy = spec.timeLimit ? m > 0.82 : m > 110;
      if (tooEasy) lo = pace; else hi = pace;
      pace = (lo + hi) / 2;
    }
    return best;
  }
  function playtestSpec(s, seconds) { return CodexEngine.playtest(s, { seconds, seeds: [3, 17, 29] }); }
  return { variants, rate, tune, playtestSpec, understand, design, edit, validateRecipe, applyRecipe, mechPrompt, wordsPrompt, parseJSON, learnWords, learnRecipe, genreProbs, trainSet, setNet, describe, lookup, title };
})();
