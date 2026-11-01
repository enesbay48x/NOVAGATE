extends RefCounted
# NOVAGATE - PILOT BIO (YETENEK AGACI)  -  DarkOrbit sistemine gore
# * Toplam en fazla 50 Ar-Ge puani. Puanlar Log Disk biriktirerek kazanilir (1 Log Disk = 300 Uridium).
# * Her yetenek: "pts" kadar seviye (her seviye 1 Ar-Ge puani) + her seviyede Kredi/Seprom bedeli.
# * Seviye k'nin bedeli = TIERS[tier] x k   (ornek: orta grup 1. seviye 100.000 Kr + 100 Seprom, 2. seviye 200.000 ...).
# * "req": on kosul {yetenek_id: asgari_seviye}.
# * I / II yeteneklerde bonuslar TOPLANMAZ: ayni "effect" icin en yuksek deger gecerlidir.

const MAX_POINTS := 50
const LOGDISK_URI := 300
const RESET_BASE_URI := 1000      # ilk sifirlama 1.000, sonra her seferinde 2 kati
const SEPROM_PER_URI := 10        # NPC oldurunce dusen Seprom = NPC'nin Uridium odulu x bu sayi (ayar)

# Toplam Log Disk (CUM[n] = n Ar-Ge puani icin gereken toplam Log Disk)
const CUM := [0, 30, 63, 99, 139, 183, 234, 287, 343, 401, 463, 544, 637, 743, 864, 1001, 1142, 1297, 1467, 1653, 1858, 2071, 2299, 2546, 2811, 3096, 3424, 3784, 4181, 4619, 5100, 5687, 6358, 7124, 8000, 9000, 10003, 11095, 12287, 13585, 15000, 16421, 17927, 19522, 21211, 23000, 25019, 27206, 29575, 32139, 34917]

const TIERS := {
	"basic": {"cr": 10000, "sep": 0, "name": "Temel"},
	"mid": {"cr": 100000, "sep": 100, "name": "Orta"},
	"adv": {"cr": 1000000, "sep": 1000, "name": "İleri"},
}

# Ikon atlasi (assets/skills/skilltree_textur.png): 25 ikon, soldan saga, ilki x=297'de, adim 74 px
const ATLAS := "res://assets/skills/skilltree_textur.png"
const ICON_X0 := 297
const ICON_STEP := 74
const ICON_W := 74
const ICON_H := 85

const BRANCHES := [
	["atk", "SALDIRI YETENEKLERİ"],
	["def", "SAVUNMA YETENEKLERİ"],
	["eco", "KAYNAK VE EKONOMİ YETENEKLERİ"],
]

const SKILLS := [
	{"id": "detonation_1", "icon": 19, "name": "Detonation I", "branch": "atk", "pts": 2, "tier": "basic", "effect": "mine_dmg", "bonus": 0.14, "req": {}, "desc": "Mayın hasarı +%14. (Detonation II için ön koşul.)  [Oyunda mayın yok: şimdilik etkisiz]"},
	{"id": "detonation_2", "icon": 20, "name": "Detonation II", "branch": "atk", "pts": 3, "tier": "mid", "effect": "mine_dmg", "bonus": 0.5, "req": {"detonation_1": 2}, "desc": "Mayın hasarı +%50. (I'in bonusuna eklenmez, onun yerine geçer.)  [Mayın yok: şimdilik etkisiz]"},
	{"id": "explosives", "icon": 0, "name": "Explosives", "branch": "atk", "pts": 5, "tier": "basic", "effect": "mine_area", "bonus": 0.25, "req": {"detonation_2": 3}, "desc": "Mayın patlama alanı +%25.  [Mayın yok: şimdilik etkisiz]"},
	{"id": "heat_seeking", "icon": 5, "name": "Heat Seeking Missiles", "branch": "atk", "pts": 5, "tier": "mid", "effect": "rocket_acc", "bonus": 0.1, "req": {"detonation_1": 2}, "desc": "Roket isabeti +%10 (roket temel isabeti %90)."},
	{"id": "rocket_fusion", "icon": 8, "name": "Rocket Fusion", "branch": "atk", "pts": 5, "tier": "adv", "effect": "rocket_dmg", "bonus": 0.15, "req": {"heat_seeking": 3}, "desc": "Roket hasarı +%15 (NPC ve oyuncuya)."},
	{"id": "alien_hunter", "icon": 18, "name": "Alien Hunter", "branch": "atk", "pts": 5, "tier": "mid", "effect": "laser_npc", "bonus": 0.12, "req": {"detonation_1": 2}, "desc": "NPC'lere lazer hasarı +%12."},
	{"id": "bounty_1", "icon": 3, "name": "Bounty Hunter I", "branch": "atk", "pts": 2, "tier": "basic", "effect": "laser_pvp", "bonus": 0.04, "req": {"shield_eng": 2}, "desc": "Oyunculara lazer hasarı +%4."},
	{"id": "bounty_2", "icon": 4, "name": "Bounty Hunter II", "branch": "atk", "pts": 3, "tier": "mid", "effect": "laser_pvp", "bonus": 0.12, "req": {"bounty_1": 2, "electro_optics": 3}, "desc": "Oyunculara lazer hasarı +%12 (I'in yerine geçer)."},
	{"id": "electro_optics", "icon": 17, "name": "Electro-Optics", "branch": "atk", "pts": 5, "tier": "adv", "effect": "laser_acc", "bonus": 0.12, "req": {"shield_mech": 5}, "desc": "Lazer isabeti +%12 (lazer temel isabeti %88)."},
	{"id": "hull_1", "icon": 15, "name": "Ship Hull I", "branch": "def", "pts": 2, "tier": "basic", "effect": "hp_flat", "bonus": 15000.0, "req": {}, "desc": "Azami can +15.000."},
	{"id": "hull_2", "icon": 16, "name": "Ship Hull II", "branch": "def", "pts": 3, "tier": "mid", "effect": "hp_flat", "bonus": 50000.0, "req": {"hull_1": 2, "bounty_1": 2}, "desc": "Azami can +50.000 (I'in yerine geçer)."},
	{"id": "engineering", "icon": 9, "name": "Engineering", "branch": "def", "pts": 5, "tier": "basic", "effect": "repair", "bonus": 0.3, "req": {"hull_1": 2}, "desc": "Can yenilenme (tamir) hızı +%30."},
	{"id": "shield_eng", "icon": 6, "name": "Shield Engineering", "branch": "def", "pts": 5, "tier": "mid", "effect": "shield_pct", "bonus": 0.25, "req": {"engineering": 1}, "desc": "Azami kalkan gücü +%25."},
	{"id": "evasive_1", "icon": 12, "name": "Evasive Maneuvers I", "branch": "def", "pts": 2, "tier": "basic", "effect": "evasion", "bonus": 0.04, "req": {"hull_1": 2}, "desc": "Düşman isabetini %4 azaltır."},
	{"id": "evasive_2", "icon": 13, "name": "Evasive Maneuvers II", "branch": "def", "pts": 3, "tier": "mid", "effect": "evasion", "bonus": 0.12, "req": {"evasive_1": 2, "shield_eng": 2}, "desc": "Düşman isabetini toplamda %12 azaltır (I'in yerine geçer)."},
	{"id": "shield_mech", "icon": 14, "name": "Shield Mechanics", "branch": "def", "pts": 5, "tier": "adv", "effect": "shield_abs", "bonus": 0.12, "req": {"hull_2": 3}, "desc": "Kalkanın hasarı karşılama oranı +%12."},
	{"id": "tactics", "icon": 1, "name": "Tactics", "branch": "eco", "pts": 5, "tier": "basic", "effect": "xp_npc", "bonus": 0.12, "req": {}, "desc": "NPC öldürmede XP +%12."},
	{"id": "logistics", "icon": 2, "name": "Logistics", "branch": "eco", "pts": 5, "tier": "basic", "effect": "cargo", "bonus": 0.25, "req": {"tactics": 1}, "desc": "Kargo kapasitesi +%25.  [Oyunda kargo yok: şimdilik etkisiz]"},
	{"id": "luck_1", "icon": 23, "name": "Luck I", "branch": "eco", "pts": 2, "tier": "basic", "effect": "box_uri", "bonus": 0.04, "req": {"tactics": 1}, "desc": "Bonus kutusundan Uridium +%4."},
	{"id": "luck_2", "icon": 24, "name": "Luck II", "branch": "eco", "pts": 3, "tier": "mid", "effect": "box_uri", "bonus": 0.12, "req": {"luck_1": 2}, "desc": "Bonus kutusundan Uridium +%12 (I'in yerine geçer)."},
	{"id": "cruelty_1", "icon": 21, "name": "Cruelty I", "branch": "eco", "pts": 2, "tier": "basic", "effect": "honor", "bonus": 0.08, "req": {"greed": 2}, "desc": "Kazanılan Şeref +%8."},
	{"id": "cruelty_2", "icon": 22, "name": "Cruelty II", "branch": "eco", "pts": 3, "tier": "mid", "effect": "honor", "bonus": 0.25, "req": {"cruelty_1": 2}, "desc": "Kazanılan Şeref +%25 (I'in yerine geçer)."},
	{"id": "greed", "icon": 7, "name": "Greed", "branch": "eco", "pts": 5, "tier": "mid", "effect": "cr_npc", "bonus": 0.25, "req": {"tactics": 2}, "desc": "NPC kredi ödülü +%25."},
	{"id": "tractor_1", "icon": 10, "name": "Tractor Beam I", "branch": "eco", "pts": 2, "tier": "basic", "effect": "loot_npc", "bonus": 0.02, "req": {"logistics": 2}, "desc": "NPC ganimeti (kredi/Seprom/Uridium) +%2."},
	{"id": "tractor_2", "icon": 11, "name": "Tractor Beam II", "branch": "eco", "pts": 3, "tier": "mid", "effect": "loot_box", "bonus": 0.12, "req": {"tractor_1": 2, "luck_1": 2}, "desc": "Bonus kutusu ganimeti +%12."},
]


static func points_for_disks(disks: int) -> int:
	var n := 0
	for i in range(1, CUM.size()):
		if disks >= int(CUM[i]):
			n = i
	return n


static func disks_for_next(disks: int) -> int:
	# bir sonraki Ar-Ge puani icin kalan Log Disk (50'de 0)
	var n := points_for_disks(disks)
	if n >= MAX_POINTS:
		return 0
	return int(CUM[n + 1]) - disks


static func find(id: String) -> Dictionary:
	for s in SKILLS:
		if str(s.id) == id:
			return s
	return {}


static func level_cost(s: Dictionary, level: int) -> Dictionary:
	# level: kacinci seviye aliniyor (1..pts)
	var t: Dictionary = TIERS[str(s.tier)]
	return {"cr": int(t.cr) * level, "sep": int(t.sep) * level}


static func total_cost(s: Dictionary) -> Dictionary:
	var cr := 0
	var sep := 0
	for k in range(1, int(s.pts) + 1):
		var c := level_cost(s, k)
		cr += int(c.cr)
		sep += int(c.sep)
	return {"cr": cr, "sep": sep}


static func icon_region(i: int) -> Rect2:
	return Rect2(float(ICON_X0 + ICON_STEP * i), 0.0, float(ICON_W), float(ICON_H))


# Yerlesim: sutun = on kosul zincirinin derinligi, satir = dal icinde bos satir.
# Doner: {id: Vector2(sutun, satir)}  (satirlar dallar arasi ust uste dizilir)
static func layout() -> Dictionary:
	var depth := {}
	var changed := true
	for s in SKILLS:
		depth[str(s.id)] = 0
	var guard := 0
	while changed and guard < 40:
		changed = false
		guard += 1
		for s in SKILLS:
			var d := 0
			for k in (s.req as Dictionary).keys():
				d = maxi(d, int(depth[str(k)]) + 1)
			if d != int(depth[str(s.id)]):
				depth[str(s.id)] = d
				changed = true
	var out := {}
	var row_base := 0
	for br in BRANCHES:
		var used := {}   # "sutun|satir" -> true
		var rows := {}   # id -> satir (dal icinde)
		var max_row := 0
		for d in range(0, 12):
			for s in SKILLS:
				if str(s.branch) != str(br[0]) or int(depth[str(s.id)]) != d:
					continue
				var pref := 0
				for k in (s.req as Dictionary).keys():
					if rows.has(str(k)):
						pref = int(rows[str(k)])
						break
				var r := pref
				while used.has("%d|%d" % [d, r]):
					r += 1
				used["%d|%d" % [d, r]] = true
				rows[str(s.id)] = r
				max_row = maxi(max_row, r)
		for s in SKILLS:
			if rows.has(str(s.id)):
				out[str(s.id)] = Vector2(float(depth[str(s.id)]), float(row_base + int(rows[str(s.id)])))
		row_base += max_row + 1
	return out
