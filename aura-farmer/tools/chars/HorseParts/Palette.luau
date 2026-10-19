--!nocheck
-- Цвета и материалы коня (подобраны по кадрам клипа).
local roblox = require("@lune/roblox")
local C = roblox.Color3.fromHex

return {
	-- мех
	fur = C("4A3B32"), -- основной коричневый (морда, шея)
	furWarm = C("6B4A37"), -- тёплый: лоб, переносица
	furDark = C("2F2623"), -- кисти, тень
	furHand = C("4A382E"), -- кисти в солнце
	furGrey = C("4B4542"), -- седоватые щёки/скулы
	chestFur = C("2A2524"),
	muzzle = C("2E2A29"),
	nose = C("1C1A1A"),
	nostril = C("070606"),
	mane = C("151212"),
	earIn = C("2B2321"),
	-- рот
	lip = C("C98A78"),
	lipDark = C("A06555"),
	mouthIn = C("3D1515"),
	tongue = C("C96F6A"),
	gum = C("DA8E8C"),
	tooth = C("F4F1EA"),
	-- глаза
	eyeWhite = C("E4D69C"),
	iris = C("3E2510"),
	pupil = C("060505"),
	-- костюм
	suit = C("4C40B8"), -- индиго-фиолетовый пиджак
	suitLight = C("5A4DC8"),
	suitDark = C("2E2575"),
	shirt = C("B4432F"), -- ржаво-красная рубашка
	shirtDark = C("8E2F22"),
	dot = C("33296A"), -- тёмно-синие точки
	dotLight = C("5B4C9A"),
	jeans = C("7086BC"),
	jeansDark = C("566BA0"),
	seam = C("C99A4A"),
	belt = C("151414"),
	croc = C("23211F"),
	shoe = C("161617"),
	sole = C("0C0C0C"),
	-- золото
	gold = C("F2C14E"), -- цепь (полированное)
	goldDeep = C("C99A2E"),
	champagne = C("E3D5AE"), -- лицевая сторона «A»
	buckleSide = C("E8BF58"),
	frame = C("E2BE5C"), -- оправа очков
	watch = C("E8C467"),
	roseGold = C("E9A68A"),
	onyx = C("0E0E12"),
	-- линзы
	lensAmber = C("C9761C"),
	lensYellow = C("F0CF2E"),
	-- гантель
	plate = C("17171A"),
	plateRim = C("222226"),
	chrome = C("C9CCD2"),
}
