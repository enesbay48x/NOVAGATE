extends RefCounted
# ============================================================================
#  RÜTBE SİSTEMİ
#   * Rütbe puanı: oyuncunun performansından formülle hesaplanır.
#   * Rütbe rozeti: puan, ŞİRKETTEKİ diğer oyuncularla kıyaslanır; yüzdelik dilime göre verilir.
#   * "A" (Admin) rozeti sıralamaya GİRMEZ: sadece admin hesabına aittir, hiçbir oyuncu alamaz.
#   * Sıralama kaynağı: bu cihazdaki hesaplar (oyunda çevrimiçi sunucu yok).
#  Rozet görselleri: res://assets/ranks/rank_1.png (en düşük) ... rank_20.png (General), rank_21.png (Admin)
# ============================================================================
const DOData = preload("res://data.gd")

const ICON_PATH := "res://assets/ranks/rank_%d.png"
const ADMIN_ICON := 21
const BOARD_SECONDS := 3600   # Sunucu sıralaması + "En iyi 10" saatte bir güncellenir
const TOP_COUNT := 10

# En yüksekten en düşüğe: [ad, kontenjan / yüzde].
# İlk 4 rütbe (General..Albay) SABİT KİŞİ SAYISIYLA verilir (şirket başına): ikinci değer kişi sayısıdır.
# Diğer rütbelerde ikinci değer, o rütbeye düşen oyuncu payıdır (%).
const FIXED_RANKS := 4                      # sabit kontenjanlı rütbe sayısı
const RANKS_TOP := [
	["General", 1], ["Tümgeneral", 2], ["Kurmay Albay", 4], ["Albay", 8], ["Acemi Albay", 1.00],
	["Kurmay Binbaşı", 1.50], ["Binbaşı", 2.00], ["Acemi Binbaşı", 2.50],
	["Uzman Yüzbaşı", 3.00], ["Yüzbaşı", 3.50], ["Acemi Yüzbaşı", 4.00],
	["Üsteğmen", 4.50], ["Teğmen", 5.00], ["Asteğmen", 6.00],
	["Uzman Çavuş", 7.00], ["Çavuş", 8.00], ["Acemi Çavuş", 9.00],
	["Acemi Pilot", 10.0], ["Uzay Pilotu", 12.39], ["Acemi Uzay Pilotu", 20.0],
]

# Gemi tipi katsayısı (x 1.000 puan). Goliath = 10.
const SHIP_COEFF := {
	"phoenix": 1, "yamato": 2, "leonov": 3, "defcom": 4, "liberator": 5, "piranha": 6, "nostromo": 7,
	"bigboy": 8, "spearhead": 8, "vengeance": 9, "goliath": 10, "aegis": 10, "citadel": 10,
}


# Admin rozeti isme göre VERİLMEZ (ADMIN adlı hesap da normal sıralamaya girer).
# Sadece kayıtta elle "admin_rank": true yazılan hesap A rozetini alır.
static func is_admin(sv: Dictionary) -> bool:
	return bool(sv.get("admin_rank", false)) or bool(sv.get("is_admin", 0))


static func icon_id(idx: int) -> int:
	return RANKS_TOP.size() - idx   # idx 0 (General) -> rank_20.png, son rütbe -> rank_1.png


# pos: şirket içi sıra (1 = en iyi), n: şirketteki oyuncu sayısı
# Sıralamada önde olan yüksek rütbeyi alır: 1 = General, 2-3 = Tümgeneral, 4-7 = Kurmay Albay, 8-15 = Albay.
# Küçük şirkette de aynı sıralama geçerlidir (ör. 5 kişilik şirkette: General, 2 Tümgeneral, 2 Kurmay Albay).
# 16. sıradan sonrası: kalan rütbeler yüzdelik dilime göre verilir (en yüksek Acemi Albay).
static func rank_index(pos: int, n: int) -> int:
	var upto := 0
	for i in FIXED_RANKS:
		upto += int(RANKS_TOP[i][1])
		if pos <= upto:
			return i
	var pct: float = float(pos) / float(maxi(n, 1)) * 100.0
	var cum := 0.0
	for i in range(FIXED_RANKS, RANKS_TOP.size()):
		cum += float(RANKS_TOP[i][1])
		if pct <= cum + 0.000001:
			return i
	return RANKS_TOP.size() - 1


static func display(e: Dictionary) -> Dictionary:
	if bool(e.get("admin", false)):
		return {"icon": ADMIN_ICON, "name": "Admin"}
	var idx: int = int(e.get("idx", RANKS_TOP.size() - 1))
	return {"icon": icon_id(idx), "name": str(RANKS_TOP[idx][0])}


static func fmt(v: float) -> String:
	var neg: bool = v < 0.0
	var s: String = str(int(absf(v)))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "." + out
	return ("-" if neg else "") + out


static func fmt_pts(v: float) -> String:
	if absf(v - roundf(v)) < 0.05:
		return fmt(roundf(v))
	return "%s,%d" % [fmt(floorf(v)), int(roundf((v - floorf(v)) * 10.0)) % 10]


static func _quests_done(sv: Dictionary) -> int:
	if sv.has("quests_done"):   # sunucu veritabanı satırı: görev sayısı hazır gelir
		return int(sv.get("quests_done", 0))
	var qd = sv.get("quests", {})
	var n := 0
	if typeof(qd) == TYPE_DICTIONARY:
		for k in qd:
			var st = qd[k]
			if typeof(st) == TYPE_DICTIONARY and bool(st.get("claimed", false)):
				n += 1
	return n


# Rütbe puanı + döküm. parts: [{label, detail, value}]
static func points(sv: Dictionary, now: float) -> Dictionary:
	var xp: float = float(sv.get("xp", 0.0))
	var hon: float = float(sv.get("hon", 0.0))
	var lv: int = DOData.level_of(xp)
	var days: int = maxi(0, int((now - float(sv.get("reg_ts", now))) / 86400.0))
	var ship: String = str(sv.get("ship", "phoenix"))
	var coeff: int = int(SHIP_COEFF.get(ship, 1))
	var pvp: int = int(sv.get("pvp_kills", 0))
	var npc: int = int(sv.get("kills", 0))
	var qn: int = _quests_done(sv)
	var pen: float = float(sv.get("rank_pen", 0.0))
	var parts: Array = [
		{"label": "Deneyim (EP)", "detail": "%s EP  ÷ 100.000" % fmt(xp), "value": xp / 100000.0},
		{"label": "Onur", "detail": "%s Onur  ÷ 100" % fmt(hon), "value": hon / 100.0},
		{"label": "Seviye", "detail": "Seviye %d  × 100" % lv, "value": float(lv) * 100.0},
		{"label": "Kayıt süresi", "detail": "%d gün  × 6" % days, "value": float(days) * 6.0},
		{"label": "Gemi tipi", "detail": "%s (katsayı %d)  × 1.000" % [ship.capitalize(), coeff], "value": float(coeff) * 1000.0},
		{"label": "Oyuncu gemisi imhası", "detail": "%d gemi  × 3" % pvp, "value": float(pvp) * 3.0},
		{"label": "NPC (uzaylı) imhası", "detail": "%d NPC  ÷ 2" % npc, "value": float(npc) / 2.0},
		{"label": "Tamamlanan görevler", "detail": "%d görev  × 100" % qn, "value": float(qn) * 100.0},
	]
	var total := 0.0
	for p in parts:
		total += float(p.value)
	return {"total": maxf(total - pen, 0.0), "parts": parts, "penalty": pen}


static func _read_sv(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if typeof(d) == TYPE_DICTIONARY else {}


static func _entry(nm: String, faction: int, sv: Dictionary, now: float, is_me: bool) -> Dictionary:
	var p: Dictionary = points(sv, now)
	return {"name": nm, "faction": faction, "pts": float(p.total), "parts": p.parts, "penalty": float(p.penalty),
		"admin": is_admin(sv), "me": is_me, "ship": str(sv.get("ship", "phoenix")),
		"pos": 0, "n": 0, "idx": RANKS_TOP.size() - 1}


# Tüm hesapları okuyup şirket içi sıralama + rütbeleri hesaplar.
# Dönen: {me: Dictionary, top: Array(<=10), total: int}
static func summary(game) -> Dictionary:
	var now: float = Time.get_unix_time_from_system()
	var me_name: String = str(game.account_name)
	if me_name == "":
		me_name = str(game.SV.get("callsign", "Gezgin"))
	var me_key: String = str(game._acc_key(me_name))
	var entries: Array = []
	var me_entry: Dictionary = {}
	var db: Dictionary = game._acc_load()
	var users: Dictionary = db.get("users", {})
	for key in users:
		var rec: Dictionary = users[key]
		var is_me: bool = str(key) == me_key
		var sv: Dictionary = game.SV if is_me else _read_sv(str(rec.get("file", "")))
		if sv.is_empty():
			continue
		var e: Dictionary = _entry(str(rec.get("name", key)), int(rec.get("faction", sv.get("faction", 1))), sv, now, is_me)
		entries.append(e)
		if is_me:
			me_entry = e
	if me_entry.is_empty():
		me_entry = _entry(me_name, int(game.SV.get("faction", 1)), game.SV, now, true)
		entries.append(me_entry)

	# Admin hiçbir sıralamaya girmez
	var players: Array = entries.filter(func(x): return not bool(x.admin))
	players.sort_custom(func(a, b):
		if float(a.pts) != float(b.pts):
			return float(a.pts) > float(b.pts)
		return str(a.name) < str(b.name))
	var counts := {}
	for e in players:
		var f: int = int(e.faction)
		counts[f] = int(counts.get(f, 0)) + 1
		e["pos"] = counts[f]
	for e in players:
		e["n"] = int(counts[int(e.faction)])
		e["idx"] = rank_index(int(e.pos), int(e.n))
	# Admin için yalnızca bilgi amaçlı "oyuncu olsaydı" sırası
	if bool(me_entry.admin):
		var above := 0
		for e in players:
			if int(e.faction) == int(me_entry.faction) and float(e.pts) > float(me_entry.pts):
				above += 1
		var same: int = int(counts.get(int(me_entry.faction), 0)) + 1
		me_entry["pos"] = above + 1
		me_entry["n"] = same
		me_entry["idx"] = rank_index(above + 1, same)
	return {"me": me_entry, "top": players.slice(0, TOP_COUNT), "total": players.size()}


# Sunucu sıralaması: TÜM hesaplar (çevrimdışı olanlar dahil) şirket içinde puana göre sıralanır.
# entries: [{acct:int, name:String, faction:int, pts:float, admin:bool, rings:int}]
# Dönen: {by_acct:{acct:{pos,n,idx,icon,pts,faction}}, top:[<=10 {name,faction,pts,idx,icon,rings}], total:int}
# Aynı puanda küçük hesap numarası önce gelir (sıralama her çalıştırmada aynı kalır).
static func build_board(entries: Array) -> Dictionary:
	var players: Array = entries.filter(func(x): return not bool(x.admin))
	players.sort_custom(func(a, b):
		if float(a.pts) != float(b.pts):
			return float(a.pts) > float(b.pts)
		return int(a.acct) < int(b.acct))
	var counts := {}
	for e in players:
		var f: int = int(e.faction)
		counts[f] = int(counts.get(f, 0)) + 1
		e["pos"] = int(counts[f])
	var by_acct := {}
	for e in players:
		var n: int = int(counts[int(e.faction)])
		var idx: int = rank_index(int(e.pos), n)
		by_acct[int(e.acct)] = {"pos": int(e.pos), "n": n, "idx": idx, "icon": icon_id(idx),
			"pts": float(e.pts), "faction": int(e.faction)}
	var top: Array = []
	for i in mini(TOP_COUNT, players.size()):
		var e: Dictionary = players[i]
		var info: Dictionary = by_acct[int(e.acct)]
		top.append({"name": str(e.name), "faction": int(e.faction), "pts": float(e.pts),
			"idx": int(info.idx), "icon": int(info.icon), "rings": int(e.get("rings", 0))})
	return {"by_acct": by_acct, "top": top, "total": players.size()}
