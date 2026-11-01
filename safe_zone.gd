extends RefCounted
# NOVAGATE - MERKEZI GUVENLI BOLGE / KAPI / CATISMA KURALLARI
# Hem istemci (main.gd, tek oyunculu) hem sunucu (net_server.gd, otoriter) AYNI fonksiyonlari kullanir.
# Durumlar BIRBIRINDEN AYRI tutulur:
#   zone      : konum olarak guvenli alan icinde miyim (BASE / PORTAL / NONE)           -> zone_kind()
#   lock      : saldirdigim icin korumam askida (saldiri + AGGRESSOR_LOCK_SEC)          -> lock_until
#   arrival   : gecici gecis korumasi (guvenli bolgeden ayri)                           -> arrive_until
#   protection: bunlardan cikan GERCEK koruma (hasar bunun uzerinden engellenir)        -> protection()
#   combat    : kapi kilidi icin catisma zamanlayicisi (hasar almaktan AYRI)            -> combat_until
# Kullanim: preload("res://safe_zone.gd") sabiti olarak.

const DOData := preload("res://data.gd")

const NONE := 0
const BASE := 1       # ussun cevresindeki guvenli bolge
const PORTAL := 2     # kapi cevresindeki guvenli bolge
const ARRIVAL := 3    # gecici gecis korumasi (normal guvenli bolge DEGIL)


static func rules(m: Dictionary) -> Dictionary:
	return m.get("rules", {})


static func is_zone_protection(kind: int) -> bool:
	return kind == BASE or kind == PORTAL


# Harita oyuncunun KENDI sirketinin haritasi mi? (4-x ve tarafsiz haritalar: faction 0 -> asla)
static func is_own_map(m: Dictionary, faction: int) -> bool:
	return faction != 0 and int(m.get("faction", 0)) == faction


# Konum olarak hangi guvenli alanin icindeyim? Sinir nettir: mesafe < yaricap -> icinde, aksi halde disinda.
# base: Vector3 | null.  portals: [{"to": String, "pos": Vector3}, ...] (solucan deligi sayilmaz)
static func zone_kind(m: Dictionary, faction: int, pos: Vector3, base: Variant, portals: Array) -> int:
	var r: Dictionary = rules(m)
	if r.is_empty():
		return NONE
	var own: bool = is_own_map(m, faction)
	if base != null and bool(r.get("base_safe_own", false)) and (own or bool(r.get("base_safe_enemy", false))):
		if pos.distance_to(base as Vector3) < DOData.SAFE_RADIUS * DOData.S:
			return BASE
	if bool(r.get("portal_safe_own" if own else "portal_safe_enemy", false)):
		var rad: float = float(r.get("portal_safe_radius", DOData.PORTAL_SAFE_RADIUS)) * DOData.S
		for p in portals:
			if str(p.get("to", "")) == "random":
				continue
			if pos.distance_to(p.pos as Vector3) < rad:
				return PORTAL
	return NONE


# Gercek koruma: saldiri kilidi her seyi iptal eder; sonra guvenli bolge; sonra gecici gecis korumasi.
static func protection(zone: int, lock_until: float, arrive_until: float, now: float) -> int:
	if now < lock_until:
		return NONE
	if zone != NONE:
		return zone
	if now < arrive_until:
		return ARRIVAL
	return NONE


static func lock_after_attack(now: float) -> float:
	return now + DOData.AGGRESSOR_LOCK_SEC


# Dusman haritasina gecince gecici koruma suresi (sn). Kendi haritanda 0.
static func arrival_seconds(m: Dictionary, faction: int) -> float:
	if is_own_map(m, faction):
		return 0.0
	return float(rules(m).get("arrival_protect_enemy_sec", 0.0))


# Kapidan atlama izni: bos string = serbest, doluysa engel nedeni.
static func jump_block_reason(m: Dictionary, now: float, combat_until: float) -> String:
	if bool(rules(m).get("jump_block_combat", false)) and now < combat_until:
		return "Savaş sırasında kapı kullanılamaz."
	return ""


# Hasar bu haritada "catisma" sayilir mi (NPC hasari dahil)?
static func npc_damage_is_combat(m: Dictionary) -> bool:
	return bool(rules(m).get("jump_block_combat", false))


static func banner_text(kind: int) -> String:
	if kind == BASE or kind == PORTAL:
		return "GÜVENLİ BÖLGE"
	if kind == ARRIVAL:
		return "GEÇİŞ KORUMASI"
	return ""
