class_name DOData
extends RefCounted
# DarkOrbit oyun verisi. "SQL" yazanlar senin server.sql dosyandan gercek degerlerdir,
# "~" yazanlar genel DarkOrbit bilgisine gore YAKLASIK degerlerdir; istedigin gibi degistir.

const S := 0.04              # 1 DarkOrbit birimi = 0.04 Godot birimi (harita 21000x13100 -> 840x524)
const SPEEDMULT := 2.0       # gemi hizi carpani (gercek hiz cok yavas hissettirir; 1.0 yaparsan orijinal)
const LASER_BASE := 60.0     # ~ lazer basina hasar
const LASER_RANGE := 700.0   # ~ lazer menzili (DO birimi)
const AGGRO_RANGE := 800.0   # ~ saldirgan NPC algilama mesafesi
const SAFE_RADIUS := 1500.0  # ~ ust guvenli bolge yaricapi
const PORTAL_RANGE := 350.0

# ---- ATIS ARALIKLARI (TEK MERKEZI AYAR; ates zamanlamasi baska hicbir yerde sabitlenmez) ----
const NPC_FIRE_INTERVAL := 0.90      # TUM NPC'ler (standart, Boss, Uber, Protegit) oyuncuya bu aralikla ates eder (sn). NPC turune gore degismez.
const PLAYER_FIRE_INTERVAL := 0.60   # Oyuncu, lazer turunden bagimsiz, bu aralikla ates eder (sn).


# Atis sayacini ates sonrasi yeniden kurar. Zaman tabanli: sayac "cd_before > 0" iken beklenip bitti ise o karedeki
# asim (en fazla bir kare = dt) bir sonraki araliktan dusulur; boylece ortalama aralik tam `interval` olur.
# Sayac zaten hazir bekliyorduysa (ilk atis, menzile yeni girme) asim tasinmaz -> ilk atistan sonraki aralik tam `interval`.
# Her cagri EN FAZLA BIR atis uretir: dusuk FPS'te ayni karede ust uste atis birikmez.
static func rearm_cd(cd_before: float, cd_now: float, dt: float, interval: float) -> float:
	var carry := 0.0
	if cd_before > 0.0:
		carry = clampf(cd_now, -dt, 0.0)
	return interval + carry


# Bir NPC atisinin TEK atis hasari. "dmg" = minimum (ya da sabit), "dmg_max" varsa her atista [dmg, dmg_max] arasinda rastgele.
# Bu DPS degil, atis basina hasardir (aralik: NPC_FIRE_INTERVAL).
static func npc_shot_damage(d: Dictionary) -> float:
	var lo: float = float(d.get("dmg", 0.0))
	var hi: float = float(d.get("dmg_max", lo))
	if hi > lo:
		return roundf(randf_range(lo, hi))
	return lo

# ---- GUVENLI BOLGE / KAPI / CATISMA AYARLARI (kurallar: safe_zone.gd; harita bazli kurallar: _attach_rules) ----
# DOGRULANAN (TR rehberi + EN wiki): 4-1..4-4 haritalarinda guvenli bolge YOK ve saldiri altindayken kapidan atlanamaz;
#   guvenli bolge ev haritalarinda, kapi cevresinde ve ussun yaninda; DUSMAN haritasinda kapi icinde saldirilabilir;
#   guvenli bolgedeyken saldirirsan koruma biter.
# DOGRULANAMAYAN (kaynaklarda sayi/kesin kural yok -> burada ayarlanabilir varsayim): asagidaki sureler/yaricaplar.
const PORTAL_SAFE_RADIUS := 600.0        # kapi cevresi guvenli yaricap (DO birimi) - varsayim
const COMBAT_SEC := 10.0                 # son PvP vurusundan sonra "catisma" sayilma suresi (sn) - varsayim
const AGGRESSOR_LOCK_SEC := 10.0         # saldiridan sonra korumanin geri gelemedigi sure (sn) - varsayim
const ARRIVAL_PROTECT_ENEMY_SEC := 0.0   # dusman haritasina gecis korumasi (sn). Kaynaklarda DOGRULANMADI -> 0 = kapali
const ADV_MAP_PORTAL_DMZ := false        # X-5..X-8'de kendi sirketinin kapi cevresi guvenli mi? Kaynak ayirmiyor -> kapali
const ENEMY_BASE_SAFE := false           # dusman ussunun yaninda guvenli bolge (kapali: sadece kendi ussun)
const JUMP_BLOCK_NORMAL_MAPS := false    # normal sirket haritalarinda saldiri altinda atlamayi engelle (kaynakta yalnizca PvP haritalari)

# MODEL YONU DUZELTMESI (derece). Oyun burnu otomatik bulur; yine de ters/yan duran bir model olursa
# buraya ekle. Ornek:  {"saimon": 180.0, "lordakia": 90.0}   (180 = ters cevir, 90 / -90 = yana cevir)
const MODEL_YAW_FIX := {}

const FACTIONS := {
	1: {"name": "MMO", "home": "1-1", "base": "building-base-mmo"},
	2: {"name": "EIC", "home": "2-1", "base": "building-base-eic"},
	3: {"name": "VRU", "home": "3-1", "base": "building-base-vru"},
}

# hp/speed/lasers/gens: SQL (goliath, vengeance, aegis, citadel, spearhead); digerleri ~yaklasik. Fiyatlar ~yaklasik.
const SHIPS := [
	{"id": "phoenix", "name": "Phoenix", "hp": 4000, "spd": 320, "las": 2, "gen": 1, "cr": 0, "uri": 0},
	{"id": "yamato", "name": "Yamato", "hp": 8000, "spd": 340, "las": 2, "gen": 2, "cr": 10000, "uri": 0},
	{"id": "leonov", "name": "Leonov", "hp": 16000, "spd": 330, "las": 3, "gen": 3, "cr": 40000, "uri": 0},
	{"id": "defcom", "name": "Defcom", "hp": 32000, "spd": 320, "las": 4, "gen": 4, "cr": 120000, "uri": 0},
	{"id": "liberator", "name": "Liberator", "hp": 64000, "spd": 320, "las": 6, "gen": 6, "cr": 300000, "uri": 0},
	{"id": "piranha", "name": "Piranha", "hp": 100000, "spd": 330, "las": 8, "gen": 8, "cr": 600000, "uri": 0},
	{"id": "nostromo", "name": "Nostromo", "hp": 128000, "spd": 330, "las": 8, "gen": 8, "cr": 1000000, "uri": 0},
	{"id": "bigboy", "name": "Bigboy", "hp": 160000, "spd": 320, "las": 10, "gen": 10, "cr": 1500000, "uri": 0},
	{"id": "spearhead", "name": "Spearhead", "hp": 100000, "spd": 370, "las": 5, "gen": 12, "cr": 0, "uri": 80000},
	{"id": "vengeance", "name": "Vengeance", "hp": 180000, "spd": 380, "las": 10, "gen": 10, "cr": 0, "uri": 100000},
	{"id": "goliath", "name": "Goliath", "hp": 256000, "spd": 300, "las": 15, "gen": 15, "cr": 0, "uri": 100000},
	{"id": "aegis", "name": "Aegis", "hp": 275000, "spd": 300, "las": 10, "gen": 15, "cr": 0, "uri": 130000},
	{"id": "citadel", "name": "Citadel", "hp": 550000, "spd": 240, "las": 7, "gen": 20, "cr": 0, "uri": 170000},
]

const AMMO := [
	{"id": "x1", "name": "LCB-10", "mult": 1.0, "price": 1000, "col": Color(1.0, 0.22, 0.16)},
	{"id": "x2", "name": "MCB-25", "mult": 2.0, "price": 2000, "col": Color(0.35, 0.72, 1.0)},
	{"id": "x3", "name": "MCB-50", "mult": 3.0, "price": 3000, "col": Color(0.3, 1.0, 0.45)},
	{"id": "x4", "name": "UCB-100", "mult": 4.0, "price": 4000, "col": Color(0.95, 1.0, 1.0)},
	{"id": "sab", "name": "SAB-50", "mult": 2.0, "price": 3000, "col": Color(0.45, 0.8, 1.0)},
	{"id": "rsb", "name": "RSB-75", "mult": 6.0, "price": 5000, "col": Color(1.0, 0.8, 0.28)},
]

# Kristallin/Kristallon/Boslar: SQL (server_ships). Digerleri ~yaklasik.
# "dmg" = NPC'nin TEK ATIS hasari (DPS degil); "dmg_max" varsa her atista dmg..dmg_max arasi rastgele. Atis araligi: NPC_FIRE_INTERVAL.
const NPCS := {
	"streuner": {"name": "Streuner", "model": "streuner", "sz": 5.0, "hp": 800, "sh": 400, "spd": 150, "dmg": 20, "aggr": false, "xp": 400, "hon": 0, "cr": 400, "uri": 1, "resp": 10.0},
	"lordakia": {"name": "Lordakia", "model": "lordakia", "sz": 5.0, "hp": 2000, "sh": 2000, "spd": 300, "dmg": 80, "aggr": true, "xp": 800, "hon": 1, "cr": 800, "uri": 2, "resp": 12.0},
	"saimon": {"name": "Saimon", "model": "saimon", "sz": 6.0, "hp": 6000, "sh": 3000, "spd": 200, "dmg": 150, "dmg_max": 200, "aggr": false, "xp": 1600, "hon": 2, "cr": 1600, "uri": 4, "resp": 15.0},
	"mordon": {"name": "Mordon", "model": "mordon", "sz": 7.0, "hp": 20000, "sh": 10000, "spd": 250, "dmg": 300, "dmg_max": 400, "aggr": true, "xp": 3200, "hon": 4, "cr": 6400, "uri": 8, "resp": 15.0},
	"devolarium": {"name": "Devolarium", "model": "devolarium", "sz": 8.0, "hp": 100000, "sh": 100000, "spd": 300, "dmg": 900, "dmg_max": 1200, "aggr": true, "xp": 6400, "hon": 8, "cr": 51200, "uri": 16, "resp": 18.0},
	"sibelon": {"name": "Sibelon", "model": "sibelon", "sz": 10.0, "hp": 200000, "sh": 200000, "spd": 250, "dmg": 2250, "dmg_max": 3000, "aggr": false, "xp": 12800, "hon": 16, "cr": 102400, "uri": 64, "resp": 20.0},
	"sibelonit": {"name": "Sibelonit", "model": "sibelonit", "sz": 6.0, "hp": 40000, "sh": 40000, "spd": 300, "dmg": 750, "dmg_max": 1000, "aggr": true, "xp": 3200, "hon": 16, "cr": 12800, "uri": 16, "resp": 20.0},
	"kristallin": {"name": "Kristallin", "model": "kristallin", "sz": 6.0, "hp": 60000, "sh": 50000, "spd": 320, "dmg": 900, "dmg_max": 1200, "aggr": true, "xp": 1600, "hon": 32, "cr": 6400, "uri": 8, "resp": 20.0},
	"kristallon": {"name": "Kristallon", "model": "kristallon", "sz": 11.0, "hp": 400000, "sh": 300000, "spd": 250, "dmg": 3750, "dmg_max": 5000, "aggr": false, "xp": 51200, "hon": 256, "cr": 409800, "uri": 128, "resp": 30.0},
	"lordakium": {"name": "Lordakium", "model": "lordakium", "sz": 13.0, "hp": 300000, "sh": 200000, "spd": 280, "dmg": 3150, "dmg_max": 3600, "aggr": true, "xp": 25600, "hon": 256, "cr": 204800, "uri": 128, "resp": 30.0},
	"boss_kristallin": {"name": "Boss Kristallin", "model": "kristallin", "sz": 9.0, "hp": 200000, "sh": 160000, "spd": 320, "dmg": 4000, "aggr": true, "xp": 25600, "hon": 128, "cr": 51200, "uri": 64, "resp": 40.0},
	"boss_kristallon": {"name": "Boss Kristallon", "model": "kristallon", "sz": 16.0, "hp": 1600000, "sh": 1200000, "spd": 250, "dmg": 18000, "aggr": false, "xp": 204800, "hon": 1024, "cr": 1638400, "uri": 512, "resp": 60.0},
	"uber_lordakium": {"name": "Uber Lordakium", "model": "lordakium", "sz": 15.0, "hp": 700000, "sh": 500000, "spd": 280, "dmg": 6000, "aggr": true, "xp": 76800, "hon": 768, "cr": 614400, "uri": 384, "resp": 90.0},
	"uber_sibelonit": {"name": "Uber Sibelonit", "model": "sibelonit", "sz": 14.0, "hp": 600000, "sh": 500000, "spd": 300, "dmg": 5000, "aggr": true, "xp": 76800, "hon": 384, "cr": 307200, "uri": 192, "resp": 80.0},
	"uber_kristallin": {"name": "Uber Kristallin", "model": "kristallin", "sz": 8.0, "hp": 500000, "sh": 400000, "spd": 320, "dmg": 5000, "aggr": true, "xp": 76800, "hon": 384, "cr": 153600, "uri": 192, "resp": 80.0},
	"uber_kristallon": {"name": "Uber Kristallon", "model": "kristallon", "sz": 18.0, "hp": 2400000, "sh": 1800000, "spd": 240, "dmg": 9000, "aggr": false, "xp": 307200, "hon": 1536, "cr": 2457600, "uri": 768, "resp": 90.0},
	"pilot": {"name": "Rakip Pilot", "model": "goliath", "sz": 7.0, "hp": 256000, "sh": 100000, "spd": 300, "dmg": 3000, "aggr": true, "xp": 51200, "hon": 512, "cr": 0, "uri": 512, "resp": 30.0},
	"streuner_boss": {"name": "StreuneR", "model": "streuner", "sz": 10.0, "hp": 30000, "sh": 20000, "spd": 200, "dmg": 350, "dmg_max": 500, "aggr": true, "xp": 3200, "hon": 64, "cr": 6400, "uri": 8, "resp": 20.0},
	"cubikon": {"name": "Cubikon", "model": "kristallon", "sz": 20.0, "hp": 1600000, "sh": 1200000, "spd": 100, "dmg": 0, "aggr": false, "xp": 409600, "hon": 1024, "cr": 1638400, "uri": 1062, "resp": 75.0},
	"protegit": {"name": "Protegit", "model": "protegit", "sz": 1.5, "hp": 50000, "sh": 40000, "spd": 320, "dmg": 1125, "dmg_max": 1500, "aggr": true, "xp": 6400, "hon": 64, "cr": 12800, "uri": 16, "resp": 3.0},
}

# ---- CUBIKON / PROTEGIT SAVUNMA SISTEMI AYARI (yapilandirilabilir) ----
# "cells" + "cell_scale": 2010 X-6 izgara referansi (75,39 / 134,39 / 75,79 / 134,79 harita izgara
# hucreleri); hücre * 140 DO birimi -> harita icine dusen dogus koordinatlari. Hücre olcegu
# DOGRULANMAMIS baslangic degeridir; gerçek harita boyutuna göre istedigin gibi degistirebilirsin.
const CUBIKON := {
	"hp": 1600000, "sh": 1200000,            # 2010 referans degerleri
	"regen_hp": 125000.0,                    # HP yenileme hizi (HP/sn) - baslangic referansi
	"regen_delay": 10.0,                     # saldiri kesildikten bu kadar sn sonra yenilenme baslar
	"cap": 30,                               # Cubikon basina azami Protegit (koruma kadrosu tavani)
	"guard_min": 20,                         # saldiri aninda cagirilan Protegit kadrosu: en az
	"guard_max": 30,                         # ... en cok (rastgele 20-30)
	"wave": 10,                              # her dalgada dogan Protegit (olenler de bu hizla yenilenir)
	"wave_gap": 1.0,                         # Protegit dalga/yenilenme araligi (sn) - hizli respawn
	"leash": 1500.0,                         # Protegit Cubikondan en fazla bu kadar uzaklasir (DO birimi)
	"leash_despawn": 4.0,                    # oyuncu leash disina cikinca Protegit'in yok olma suresi (sn)
	"swarm_r_min": 14.0,                     # suru yorunge yaricapi (Godot birimi; Cubikon govdesi ~10)
	"swarm_r_max": 30.0,
	"swarm_w_min": 0.35,                     # suru yorunge acisal hizi (rad/sn)
	"swarm_w_max": 0.80,
	"engage_range": 1200.0,                  # oyuncu Cubikona bu kadar yaklasinca (DO birimi) Protegit ates edebilir
	"guard_range": 900.0,                    # ... ve Protegit'in kendisine mesafesi de bu kadar olmali
	# Protegit atis araligi = NPC_FIRE_INTERVAL (tum NPC'ler ayni; eski rastgele fire_gap_min/max kaldirildi).
	"fire_lock": 0.0,                        # ayni Cubikonun Protegitleri arasi asgari atis boslugu (sn). 0 = kapali: aksi halde 0.90 sn garanti edilemez.
	"clean_after": 15.0,                     # Cubikon olumunden sonra Protegit temizlik suresi (sn)
	"resp": 75.0,                            # Cubikon geri donus suresi (sn)
	"cells": [[75, 39], [134, 39], [75, 79], [134, 79]],
	"cell_scale": 140.0,
}

# Harita yapisi: 2010 DarkOrbit uyumlu harita yapisi.
const STD_MAP_W := 20800.0   # 208 x 133 birim
const STD_MAP_H := 13300.0
const BIG_MAP_W := 41800.0   # 418 x 268 birim (4-4, 4-5)
const BIG_MAP_H := 26800.0


static func make_maps() -> Dictionary:
	var m := {}

	# --- Faction maps X-1 through X-8 ---
	for f in [1, 2, 3]:
		# X-1: streuner, base, portal to X-2
		m["%d-1" % f] = {
			"name": "%d-1" % f,
			"w": 21000.0,
			"h": 13100.0,
			"npcs": [["streuner", 16]],
			"portals": [{"to": "%d-2" % f, "x": 19000, "y": 6500}],
			"faction": f,
			"base": {"x": 1600.0, "y": 1600.0},
			"pvp": false
		}

		# X-2: streuner, lordakia, portals to X-1, X-3, X-4
		m["%d-2" % f] = {
			"name": "%d-2" % f,
			"w": 21000.0,
			"h": 13100.0,
			"npcs": [["streuner", 8], ["lordakia", 12]],
			"portals": [
				{"to": "%d-1" % f, "x": 2000, "y": 6500},
				{"to": "%d-3" % f, "x": 19000, "y": 2000},
				{"to": "%d-4" % f, "x": 19000, "y": 11000}
			],
			"faction": f,
			"base": null,
			"pvp": false
		}

		# X-3: lordakia, saimon, mordon, portals to X-2, X-4
		m["%d-3" % f] = {
			"name": "%d-3" % f,
			"w": 21000.0,
			"h": 13100.0,
			"npcs": [["lordakia", 8], ["saimon", 6], ["mordon", 6], ["devolarium", 2]],
			"portals": [
				{"to": "%d-2" % f, "x": 2000, "y": 2000},
				{"to": "%d-4" % f, "x": 19000, "y": 11000}
			],
			"faction": f,
			"base": null,
			"pvp": false
		}

		# X-4: lordakia, saimon, sibelon, portals to X-2, X-3, 4-f
		m["%d-4" % f] = {
			"name": "%d-4" % f,
			"w": 21000.0,
			"h": 13100.0,
			"npcs": [["lordakia", 8], ["saimon", 6], ["sibelon", 4]],
			"portals": [
				{"to": "%d-2" % f, "x": 2000, "y": 2000},
				{"to": "%d-3" % f, "x": 2000, "y": 11000},
				{"to": "4-%d" % f, "x": 19000, "y": 6500}
			],
			"faction": f,
			"base": null,
			"pvp": false
		}

		# X-5: sibelon, lordakia, portals to X-6, X-7, 4-4, 4-5
		m["%d-5" % f] = {
			"name": "%d-5" % f,
			"w": 21000.0,
			"h": 13100.0,
			"npcs": [["lordakia", 6], ["sibelonit", 6], ["lordakium", 2]],
			"portals": [
				{"to": "%d-6" % f, "x": 19000, "y": 2000},
				{"to": "%d-7" % f, "x": 19000, "y": 11000},
				{"to": "4-4", "x": 2000, "y": 11000},
				{"to": "4-5", "x": 2000, "y": 2000}
			],
			"faction": f,
			"base": null,
			"pvp": false
		}

		# X-6: kristallin, kristallon, portals to X-5, X-8
		m["%d-6" % f] = {
			"name": "%d-6" % f,
			"w": 21000.0,
			"h": 13100.0,
			"npcs": [["kristallin", 6], ["kristallon", 2], ["boss_kristallon", 1], ["cubikon", 4]],
			"portals": [
				{"to": "%d-5" % f, "x": 2000, "y": 6500},
				{"to": "%d-8" % f, "x": 19000, "y": 11000}
			],
			"faction": f,
			"base": null,
			"pvp": false
		}

		# X-7: kristallin, kristallon, portals to X-5, X-6
		m["%d-7" % f] = {
			"name": "%d-7" % f,
			"w": 21000.0,
			"h": 13100.0,
			"npcs": [["kristallin", 5], ["kristallon", 2], ["boss_kristallin", 1]],
			"portals": [
				{"to": "%d-5" % f, "x": 2000, "y": 2000},
				{"to": "%d-6" % f, "x": 19000, "y": 6500}
			],
			"faction": f,
			"base": null,
			"pvp": false
		}

		# X-8: streuner, base, portals to X-6, X-7; StreuneR (Boss) da bu haritada devriye gezer
		m["%d-8" % f] = {
			"name": "%d-8" % f,
			"w": 21000.0,
			"h": 13100.0,
			"npcs": [["streuner", 10], ["streuner_boss", 2]],
			"portals": [
				{"to": "%d-6" % f, "x": 2000, "y": 6500},
				{"to": "%d-7" % f, "x": 2000, "y": 11000}
			],
			"faction": f,
			"base": {"x": 1600.0, "y": 1600.0},
			"pvp": false
		}

	# --- PvP Maps 4-X ---
	m["4-1"] = {
		"name": "4-1",
		"w": 21000.0,
		"h": 13100.0,
		"npcs": [],
		"portals": [
			{"to": "1-4", "x": 10000, "y": 6200},
			{"to": "4-4", "x": 18900, "y": 1900}
		],
		"faction": 1,
		"pvp": true,
		"base": null
	}

	m["4-2"] = {
		"name": "4-2",
		"w": 21000.0,
		"h": 13100.0,
		"npcs": [],
		"portals": [
			{"to": "2-4", "x": 10400, "y": 6300},
			{"to": "4-4", "x": 18900, "y": 10900}
		],
		"faction": 2,
		"pvp": true,
		"base": null
	}

	m["4-3"] = {
		"name": "4-3",
		"w": 21000.0,
		"h": 13100.0,
		"npcs": [],
		"portals": [
			{"to": "3-4", "x": 10300, "y": 6600},
			{"to": "4-4", "x": 18900, "y": 14500}
		],
		"faction": 3,
		"pvp": true,
		"base": null
	}

	m["4-4"] = {
		"name": "4-4 (PvP)",
		"w": 42000.0,
		"h": 26000.0,
		"npcs": [["pilot", 6]],
		"faction": 0,
		"pvp": true,
		"base": null,
		"portals": [
			{"to": "4-1", "x": 21000, "y": 13500},
			{"to": "4-2", "x": 28000, "y": 1400},
			{"to": "4-3", "x": 28000, "y": 25600},
			{"to": "1-5", "x": 7000, "y": 13500},
			{"to": "2-5", "x": 35000, "y": 6500},
			{"to": "3-5", "x": 35000, "y": 19500}
		]
	}

	m["4-5"] = {
		"name": "4-5",
		"w": 21000.0,
		"h": 13100.0,
		"npcs": [["streuner", 10], ["lordakia", 10], ["saimon", 8], ["mordon", 6], ["sibelon", 4], ["kristallin", 4], ["kristallon", 2], ["uber_sibelonit", 1], ["uber_lordakium", 1], ["uber_kristallin", 1], ["uber_kristallon", 1]],
		"portals": [
			{"to": "1-5", "x": 2000, "y": 2000},
			{"to": "2-5", "x": 2000, "y": 11000},
			{"to": "3-5", "x": 2000, "y": 24000},
			{"to": "5-1", "x": 40000, "y": 13000}
		],
		"faction": 0,
		"pvp": true,
		"base": null
	}

	# --- Standart harita boyutlari (DO birimi) ---
	# Sirket haritalari ve 4-1/4-2/4-3: 208 x 133  |  4-4 ve 4-5: 418 x 268
	# Portal ve ust koordinatlari yeni boyuta oranlanir; olmayan haritaya giden kapilar silinir.
	for k in m:
		var mm: Dictionary = m[k]
		var big: bool = (k == "4-4" or k == "4-5")
		var nw: float = BIG_MAP_W if big else STD_MAP_W
		var nh: float = BIG_MAP_H if big else STD_MAP_H
		var ow: float = float(mm.w)
		var oh: float = float(mm.h)
		if k == "4-5":
			# 4-5 koordinatlari zaten buyuk harita icin yazilmisti (42000 x 26000).
			ow = 42000.0
			oh = 26000.0
			var bigger: Array = []
			for ent in mm.npcs:
				bigger.append([ent[0], int(ent[1]) * 2])
			mm.npcs = bigger
		var sx: float = nw / ow
		var sy: float = nh / oh
		var ports: Array = []
		for p in mm.portals:
			if not m.has(str(p.to)):
				continue
			p.x = float(p.x) * sx
			p.y = float(p.y) * sy
			ports.append(p)
		mm.portals = ports
		if mm.get("base") != null:
			mm.base.x = float(mm.base.x) * sx
			mm.base.y = float(mm.base.y) * sy
		mm.w = nw
		mm.h = nh

	# --- Kapi konumlari (DarkOrbit duzeni) - nihai harita koordinatlariyla ---
	var cx: float = STD_MAP_W / 2.0
	var cy: float = STD_MAP_H / 2.0
	# X-4: kendi savas haritasina (4-1/4-2/4-3) giden kapi HARITA MERKEZINDE
	for f in [1, 2, 3]:
		for p in m["%d-4" % f].portals:
			if str(p.to) == "4-%d" % f:
				p.x = cx
				p.y = cy
	# 4-1 / 4-2 / 4-3: merkezde 4-4'e giden kapi + sol ortada X-4'e donus kapisi
	for f in [1, 2, 3]:
		m["4-%d" % f].portals = [
			{"to": "4-4", "x": cx, "y": cy},
			{"to": "%d-4" % f, "x": 2500.0, "y": cy},   # donus kapisi: sirketin X-4 haritasina
		]
	# 4-4: merkezde ucgen olusturan 3 ic kapi + disarida 3 dis kapi
	var bx: float = BIG_MAP_W / 2.0
	var by: float = BIG_MAP_H / 2.0
	var tr := 2000.0
	m["4-4"].portals = [
		{"to": "4-1", "x": bx - tr, "y": by},
		{"to": "4-2", "x": bx + tr * 0.5, "y": by - tr * 0.866},
		{"to": "4-3", "x": bx + tr * 0.5, "y": by + tr * 0.866},
		{"to": "1-5", "x": 3000.0, "y": by},
		{"to": "2-5", "x": BIG_MAP_W - 3000.0, "y": 4000.0},
		{"to": "3-5", "x": BIG_MAP_W - 3000.0, "y": BIG_MAP_H - 4000.0},
	]
	# 4-5: yalnizca gorunmez solucan deligi (J ile rastgele haritaya isinlanir)
	m["4-5"].portals = [{"to": "random", "x": 21000.0, "y": 13000.0, "wormhole": true}]

	# Her haritaya yapilandirilmis dogus bolgelerini ekle (zones).
	for k in m:
		_attach_zones(m[k])
		_attach_rules(m[k], str(k))

	return m


# Her haritaya guvenli bolge / PvP / kapi kurallari ekler ("rules"). Kurallar harita numarasina degil bu yapilandirmaya baglidir;
# sirketin kendi haritasi mi dusman haritasi mi oldugu calisma aninda oyuncunun sirketiyle karsilastirilir (safe_zone.gd).
static func _attach_rules(mm: Dictionary, key: String) -> void:
	var r := {
		"kind": "", "base_safe_own": false, "base_safe_enemy": false,
		"portal_safe_own": false, "portal_safe_enemy": false, "portal_safe_radius": PORTAL_SAFE_RADIUS,
		"jump_block_combat": false, "arrival_protect_enemy_sec": 0.0,
	}
	if key == "4-1" or key == "4-2" or key == "4-3":
		r.kind = "battle"          # PvP savas haritasi: guvenli bolge yok, savasta kapi kilitli
		r.jump_block_combat = true
	elif key == "4-4":
		r.kind = "battle_hub"      # tarafsiz PvP merkezi: guvenli bolge yok, savasta kapi kilitli
		r.jump_block_combat = true
	elif key == "4-5":
		r.kind = "event_uber"      # uber NPC haritasi: guvenli bolge yok; kapi kilidi kaynakta belirsiz -> PvP gibi ele alindi
		r.jump_block_combat = true
	else:
		var n: int = int(key.get_slice("-", 1))
		r.kind = "company_start" if n == 1 else ("company_home" if n <= 4 else "company_adv")
		r.base_safe_own = true
		r.base_safe_enemy = ENEMY_BASE_SAFE
		r.portal_safe_own = (n <= 4) or ADV_MAP_PORTAL_DMZ
		r.portal_safe_enemy = false
		r.arrival_protect_enemy_sec = ARRIVAL_PROTECT_ENEMY_SEC
		r.jump_block_combat = JUMP_BLOCK_NORMAL_MAPS
	mm["rules"] = r


# Her harita icin yapilandirilmis NPC dogus verisi uretir ("zones").
# zones: [{"npc": <npc_id>, "n": <adet>, "area": [x0,y0,x1,y1] (DO birimi) | "fixed": [x,y]}] 
# - Cubikon "fixed" (sabit) hucrlerden dogar; digerleri "area" bolgelerinden, harita sinirlari,
#   portal ve us konumlarina gore denetlenerek dogar.
# - Bolgeler dort ceyrege dagitilir; boylece ayni tur NPC'ler ust uste binmez.
static func _attach_zones(m: Dictionary) -> void:
	var ratio: float = float(m.w) / 21000.0
	var ratio_h: float = float(m.h) / 13100.0
	var quad: Array = [
		[1500.0, 1500.0, 9800.0, 6200.0],
		[11200.0, 1500.0, 19500.0, 6200.0],
		[1500.0, 6900.0, 9800.0, 11600.0],
		[11200.0, 6900.0, 19500.0, 11600.0],
	]
	for qi in quad.size():
		var r: Array = quad[qi]
		r[0] = float(r[0]) * ratio
		r[1] = float(r[1]) * ratio_h
		r[2] = float(r[2]) * ratio
		r[3] = float(r[3]) * ratio_h
	var slot := 0
	var zones: Array = []
	for ent in m.get("npcs", []):
		var npc: String = str(ent[0])
		var n: int = int(ent[1])
		if npc == "cubikon":
			# Cubikon: dort sabit hucreden dogar (2010 X-6 referans hucreleri).
			for c in CUBIKON.cells:
				zones.append({
					"npc": npc,
					"n": 1,
					"fixed": [float(c[0]) * float(CUBIKON.cell_scale), float(c[1]) * float(CUBIKON.cell_scale)],
					"boss": true,
				})
			continue
		var half: int = n / 2
		var rest: int = n - half
		if rest > 0:
			zones.append({"npc": npc, "n": rest, "area": (quad[slot % 4] as Array).duplicate()})
			slot += 1
		if half > 0:
			zones.append({"npc": npc, "n": half, "area": (quad[slot % 4] as Array).duplicate()})
			slot += 1
		if slot % 4 == 0:
			slot += 1   # sonraki NPC turu farkli ceyrede baslasin
	m["zones"] = zones

static func level_of(xp: float) -> int:
	var lv := 1
	var need := 10000.0
	while xp >= need and lv < 30:
		lv += 1
		need *= 2.0
	return lv


# ------------------------------------------------------------------ TECHIZAT VERISI (~ yaklasik degerler, istedigin gibi degistir)
# Lazer: "dmg" = tek lazerin salvo basina hasari. col = mermi rengi, w = kalinlik, len = uzunluk, spd = mermi hizi.
const LASER_ORDER := ["lf1", "lf2", "lf3", "lf4"]
const LASERS := {
	"lf1": {"name": "LF-1", "dmg": 40, "cr": 10000, "uri": 0, "col": Color(1.0, 0.35, 0.3), "w": 0.12, "len": 1.8, "spd": 90.0, "desc": "Temel lazer topu."},
	"lf2": {"name": "LF-2", "dmg": 100, "cr": 0, "uri": 5000, "col": Color(0.4, 1.0, 0.45), "w": 0.16, "len": 2.3, "spd": 96.0, "desc": "Gelistirilmis lazer."},
	"lf3": {"name": "LF-3", "dmg": 150, "cr": 0, "uri": 10000, "col": Color(0.35, 0.8, 1.0), "w": 0.20, "len": 2.9, "spd": 104.0, "desc": "Agir lazer, genis demet."},
	"lf4": {"name": "LF-4", "dmg": 230, "cr": 0, "uri": 60000, "col": Color(0.8, 0.4, 1.0), "w": 0.25, "len": 3.6, "spd": 112.0, "desc": "En guclu lazer, cift cekirdekli demet."},
}

# Jeneratorler: type "spd" = hiz bonusu (DO birimi), type "sh" = kalkan kapasitesi + soguruma orani (abs)
const GEN_ORDER := ["g3n-1010", "g3n-2010", "g3n-3210", "g3n-3310", "g3n-6900", "g3n-7900", "sg3n-a01", "sg3n-a02", "sg3n-a03", "sg3n-b01", "sg3n-b02"]
const GENS := {
	"g3n-1010": {"name": "G3N-1010", "type": "spd", "val": 4, "abs": 0.8, "cr": 3000, "uri": 0},
	"g3n-2010": {"name": "G3N-2010", "type": "spd", "val": 6, "abs": 0.8, "cr": 8000, "uri": 0},
	"g3n-3210": {"name": "G3N-3210", "type": "spd", "val": 8, "abs": 0.8, "cr": 20000, "uri": 0},
	"g3n-3310": {"name": "G3N-3310", "type": "spd", "val": 10, "abs": 0.8, "cr": 50000, "uri": 0},
	"g3n-6900": {"name": "G3N-6900", "type": "spd", "val": 14, "abs": 0.8, "cr": 120000, "uri": 0},
	"g3n-7900": {"name": "G3N-7900", "type": "spd", "val": 18, "abs": 0.8, "cr": 0, "uri": 600},
	"sg3n-a01": {"name": "SG3N-A01", "type": "sh", "val": 1500, "abs": 0.80, "cr": 4000, "uri": 0},
	"sg3n-a02": {"name": "SG3N-A02", "type": "sh", "val": 2500, "abs": 0.80, "cr": 12000, "uri": 0},
	"sg3n-a03": {"name": "SG3N-A03", "type": "sh", "val": 4000, "abs": 0.80, "cr": 35000, "uri": 0},
	"sg3n-b01": {"name": "SG3N-B01", "type": "sh", "val": 6000, "abs": 0.85, "cr": 100000, "uri": 0},
	"sg3n-b02": {"name": "SG3N-B02", "type": "sh", "val": 9000, "abs": 0.90, "cr": 0, "uri": 800},
}

# Droidler: dmg / sh = tanesi basina hasar / kalkan bonusu (orani)
const DRONE_ORDER := ["flax", "iris"]
const DRONES := {
	"flax": {"name": "Flax", "dmg": 0.05, "sh": 0.10, "slots": 1, "cr": 60000, "uri": 0, "col": Color(1.0, 0.6, 0.25), "desc": "Gemiye takilan droid. Geminin etrafinda ucar ve kendi lazeri ile ateş eder."},
	"iris": {"name": "Iris", "dmg": 0.0, "sh": 0.0, "slots": 2, "cr": 60000, "uri": 0, "col": Color(0.4, 0.85, 1.0), "desc": "Gemiye takilan droid. Geminin etrafinda ucar ve kendi lazeri ile ateş eder."},
}

# Droid formasyonlari (ikonlar CMS'ten): dmg / sh / spd = ek bonus (oran)
const FORM_ORDER := ["std", "tu", "ar", "la", "st", "pi", "da", "di", "ch", "mo", "cr", "he", "ba"]
const FORMS := {
	"std": {"name": "Standart halka", "dmg": 0.0, "sh": 0.0, "spd": 0.0, "cr": 0},
	"tu": {"name": "Kaplumbağa", "dmg": 0.0, "sh": 0.10, "spd": 0.0, "cr": 25000},
	"ar": {"name": "Ok", "dmg": 0.06, "sh": 0.0, "spd": 0.0, "cr": 25000},
	"la": {"name": "Mızrak", "dmg": 0.08, "sh": -0.04, "spd": 0.0, "cr": 30000},
	"st": {"name": "Yıldız", "dmg": 0.04, "sh": 0.04, "spd": 0.0, "cr": 35000},
	"pi": {"name": "Kıskaç", "dmg": 0.05, "sh": 0.0, "spd": 0.02, "cr": 40000},
	"da": {"name": "Çift Ok", "dmg": 0.07, "sh": 0.0, "spd": 0.0, "cr": 45000},
	"di": {"name": "Elmas", "dmg": 0.02, "sh": 0.06, "spd": 0.0, "cr": 50000},
	"ch": {"name": "Şevron", "dmg": 0.05, "sh": 0.02, "spd": 0.0, "cr": 55000},
	"mo": {"name": "Güve", "dmg": 0.03, "sh": 0.0, "spd": 0.05, "cr": 60000},
	"cr": {"name": "Yengeç", "dmg": 0.02, "sh": 0.08, "spd": 0.0, "cr": 70000},
	"he": {"name": "Kalp", "dmg": 0.05, "sh": 0.05, "spd": 0.0, "cr": 80000},
	"ba": {"name": "Baraj", "dmg": 0.10, "sh": -0.05, "spd": 0.0, "cr": 90000},
}


const MAX_DRONES := 10


static func drone_slots(_ship: Dictionary) -> int:
	# Her gemi, jenerator sayisindan bagimsiz olarak 10 droid tasiyabilir.
	return MAX_DRONES


static func ship_icon(id: String, faction: int) -> String:
	if id == "aegis" or id == "citadel" or id == "spearhead":
		return "ship_%s-%s" % [id, ["mmo", "mmo", "eic", "vru"][clampi(faction, 0, 3)]]
	return "ship_" + id


# Formasyon konumlari: gemiye gore yerel (z = ileri). n droid icin n konum dondurur.
static func form_offsets(code: String, n: int) -> Array:
	var out := []
	for i in n:
		var k := float(i / 2 + 1)
		var side := -1.0 if i % 2 == 0 else 1.0
		var a := TAU * float(i) / float(maxi(n, 1))
		var p := Vector3.ZERO
		match code:
			"tu":
				p = Vector3(sin(a) * 4.6, 0, cos(a) * 4.6)
			"ar":
				p = Vector3(side * 1.5 * k, 0, 7.0 - k * 1.7)
			"la":
				p = Vector3(side * 3.6, 0, 4.5 - float(i / 2) * 1.6)
			"st":
				var r := 7.0 if i % 2 == 0 else 4.2
				p = Vector3(sin(a) * r, 0, cos(a) * r)
			"pi":
				var ang := deg_to_rad(15.0 + float(i / 2) * 16.0)
				p = Vector3(side * sin(ang) * 6.5, 0, cos(ang) * 6.5)
			"da":
				if i % 4 < 2:
					p = Vector3(side * 1.3 * k, 0, 7.0 - k * 1.2)
				else:
					p = Vector3(side * 1.3 * k, 0, -2.0 - k * 1.2)
			"di":
				var d := 6.0 / (absf(sin(a)) + absf(cos(a)))
				p = Vector3(sin(a) * d, 0, cos(a) * d)
			"ch":
				p = Vector3(side * 1.6 * k, 0, 1.5 - k * 1.5)
			"mo":
				p = Vector3(side * (2.8 + k * 1.5), 0, -0.6 * k - 1.0)
			"cr":
				if i < 2:
					p = Vector3(side * 1.6, 0, 6.5)
				else:
					p = Vector3(side * (3.6 + float(i / 2) * 0.7), 0, 3.0 - float(i / 2) * 1.5)
			"he":
				var t := TAU * float(i) / float(maxi(n, 1))
				p = Vector3(16.0 * pow(sin(t), 3.0), 0, 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)) * 0.42
			"ba":
				p = Vector3((float(i) - float(n - 1) * 0.5) * 1.6, 0, 6.5)
			_:
				p = Vector3(sin(a) * 5.6, 0, cos(a) * 5.6)
		out.append(p)
	return out
