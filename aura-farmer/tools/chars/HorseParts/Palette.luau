--!nocheck
-- Цвета и материалы коня (подобраны по кадрам клипа S02/S04/S05/S06/S08/S09/S10/S11).
local roblox = require("@lune/roblox")
local C = roblox.Color3.fromHex

return {
	-- ===== мех головы =====
	forehead = C("3A2821"), -- тёмный шоколад: лоб, темя
	warm = C("7A4634"), -- тёплый рыже-коричневый: вокруг глаз, переносица
	warmLight = C("8E5640"), -- светлая «проточина» на переносице
	bridgeLow = C("5A3A2E"), -- низ переносицы (переход к морде)
	cheek = C("5F554E"), -- седые лохматые щёки
	frost = C("9A9087"), -- светлые кончики шерсти
	jowl = C("47403B"), -- ганаши, нижняя челюсть
	neck = C("3A2C26"), -- шея
	furDark = C("251C19"), -- брови, глубокие тени
	muzzle = C("3A3634"), -- бархатная угольная морда (мягкая, не чёрная)
	nosePad = C("433E3B"), -- передняя «подушка» носа
	nostril = C("0D0A0A"), -- ноздри (полость)
	nostrilRim = C("4B4542"), -- валик ноздри
	mane = C("141111"), -- чёрный кок-помпадур
	maneHi = C("2B2522"),
	earOut = C("4A3327"),
	earIn = C("2A1E1A"),
	earTip = C("241A16"),
	-- ===== рот =====
	lip = C("BC7D6B"), -- мясистые розово-бежевые губы
	lipDark = C("93594B"), -- внутренняя кромка губ
	gum = C("D88A85"),
	tooth = C("F3EEE1"), -- «человеческие» зубы цвета слоновой кости
	toothShade = C("E2DACA"),
	mouthIn = C("7A2E24"), -- нёбо/полость (тёплое красное)
	throat = C("2A0F0C"),
	tongue = C("C9726A"),
	-- ===== глаза =====
	eyeWhite = C("D8C79A"),
	iris = C("6E5019"),
	pupil = C("050404"),
	lid = C("4E3024"),
	-- ===== тело =====
	chestFur = C("2B2320"),
	chestFrost = C("514843"),
	hand = C("4C392E"), -- кисти (мех)
	handLight = C("5E4637"), -- кончики/костяшки на свету
	handDark = C("35281F"), -- ладонь, складки
	-- ===== костюм =====
	suit = C("4A42BA"), -- индиго-фиолетовый атласный пиджак
	suitLight = C("5A52CC"), -- лацканы, блики атласа
	suitDark = C("2B2574"), -- складки, изнанка
	suitDeep = C("1C1850"), -- глубина рукава/кармана
	shirt = C("B4442E"), -- ржаво-красная рубашка
	shirtDark = C("7E2B1F"),
	dot = C("33296A"), -- тёмно-сине-фиолетовые точки
	dotLight = C("5B4C9A"),
	jeans = C("7086BA"), -- светлый деним
	jeansLight = C("8098C8"),
	jeansDark = C("566C9C"),
	seam = C("C99A4A"),
	belt = C("141313"),
	croc = C("2A2826"),
	shoe = C("171718"),
	shoeHi = C("2A2A2D"),
	sole = C("0C0C0C"),
	-- ===== золото =====
	gold = C("F0C04A"), -- полированное (цепь, кольца)
	goldDeep = C("B88A2A"),
	champagne = C("DCCFA6"), -- сатиновое лицо «A»
	buckleSide = C("E8C060"), -- полированный кант «A»
	frame = C("E2BE5C"), -- оправа очков
	watch = C("E6C266"),
	watchFace = C("EFE6C8"),
	roseGold = C("E3A08A"),
	onyx = C("0E0E12"),
	-- ===== линзы =====
	lensAmber = C("C9761C"),
	lensYellow = C("F0CF2E"),
	-- ===== гантель =====
	plate = C("17171A"),
	plateRim = C("222226"),
	chrome = C("C9CCD2"),
	-- временные псевдонимы (старые имена)
	fur = C("4A3B32"),
	furWarm = C("6B4A37"),
	furHand = C("4C392E"),
	furGrey = C("4A403B"),
	nose = C("292423"),
}
