extends RefCounted
# NOVAGATE - KLAN SISTEMI ISTEMCI TARAFI
# Sunucudan gelen klan durumunu tutar; kontrol paneli (Klan sekmesi), isim etiketi, minimap ve klan sohbeti buradan beslenir.
# Tum islemler genel olay kanalindan gider (Net.send_event) - yeni RPC yok, eski istemciler bozulmaz.
#   istemci -> sunucu: "clan_op" {op, args}, "clan_chat" {text}
#   sunucu -> istemci: "clan_state", "clan_list", "clan_result", "clan_tags", "clan_chat"

const ROLE_MEMBER := 0
const ROLE_OFFICER := 1
const ROLE_LEADER := 2
const ROLE_NAMES := ["Üye", "Subay", "Lider"]

var g                          # main.gd
var net: Node                  # Net autoload
var has_state: bool = false
var clan: Dictionary = {}      # bos = klanda degilim. {id,name,tag,description,role,max,members[],requests[],invited[]}
var invites: Array = []        # klana davetler (klansizken)
var applied: Array = []        # gonderdigim basvurular (klansizken)
var list: Array = []           # klan arama sonucu
var list_loaded: bool = false
var cost: int = 0
var my_acct: int = 0
var tags: Dictionary = {}      # peer -> [clan_id, tag]  (haritadaki herkes icin)
var last_msg: String = ""
var last_ok: bool = true
var changed: Callable          # arayuz yenileme geri cagrisi


func _init(main_node, net_node: Node) -> void:
	g = main_node
	net = net_node


# ------------------------------------------------------------------ sorgular
func in_clan() -> bool:
	return not clan.is_empty()


func my_clan_id() -> int:
	return int(clan.get("id", 0))


func my_tag() -> String:
	return str(clan.get("tag", ""))


func my_role() -> int:
	return int(clan.get("role", 0))


func can_manage() -> bool:
	return my_role() >= ROLE_OFFICER


func is_leader() -> bool:
	return my_role() == ROLE_LEADER


func tag_of(peer: int) -> String:
	var t = tags.get(peer)
	return str(t[1]) if t != null else ""


func is_clanmate(peer: int) -> bool:
	var cid: int = my_clan_id()
	if cid == 0 or peer == net.my_id:
		return false
	var t = tags.get(peer)
	return t != null and int(t[0]) == cid


func online_count() -> int:
	var n := 0
	for m in (clan.get("members", []) as Array):
		if bool(m.get("on", false)):
			n += 1
	return n


# ------------------------------------------------------------------ istekler
func request_state() -> void:
	if net.online:
		net.send_event("clan_op", {"op": "me", "args": {}})


func request_list(q: String = "") -> void:
	if net.online:
		net.send_event("clan_op", {"op": "list", "args": {"q": q}})


func op(name: String, args: Dictionary = {}) -> void:
	if net.online:
		net.send_event("clan_op", {"op": name, "args": args})
	else:
		_say("Sunucuya bağlı değilsin.", false)


func send_chat(text: String) -> void:
	if net.online:
		net.send_event("clan_chat", {"text": text})


# ------------------------------------------------------------------ sunucudan gelenler
func on_event(tip: String, veri: Dictionary) -> void:
	match tip:
		"clan_state":
			var c = veri.get("clan", null)
			clan = (c as Dictionary).duplicate(true) if typeof(c) == TYPE_DICTIONARY else {}
			invites = veri.get("invites", []) as Array
			applied = veri.get("applied", []) as Array
			cost = int(veri.get("cost", 0))
			my_acct = int(veri.get("my_acct", 0))
			has_state = true
			_after_state()
		"clan_list":
			list = veri.get("clans", []) as Array
			list_loaded = true
			_notify()
		"clan_result":
			_say(str(veri.get("msg", "")), bool(veri.get("ok", false)))
		"clan_tags":
			var t = veri.get("t", {})
			tags = (t as Dictionary).duplicate() if typeof(t) == TYPE_DICTIONARY else {}
			if g != null and g.has_method("refresh_clan_plates"):
				g.refresh_clan_plates()
			_notify()
		"clan_chat":
			if g != null and g.dohud != null and g.dohud.has_method("_log_clan"):
				var nm: String = str(veri.get("nm", "")).replace("[", "[lb]")
				var rl: int = clampi(int(veri.get("role", 0)), 0, 2)
				var col: String = ["#7dff9a", "#ffd45a", "#ff9a3c"][rl]
				var mark: String = ["", "*", "#"][rl]
				g.dohud._log_clan("[color=%s][b]%s%s:[/b][/color] %s" % [col, mark, nm, str(veri.get("text", "")).replace("[", "[lb]")])


func _after_state() -> void:
	if g != null and g.dohud != null and g.dohud.has_method("set_clan_tab"):
		g.dohud.set_clan_tab(in_clan())
	if g != null and g.has_method("refresh_clan_plates"):
		g.refresh_clan_plates()
	_notify()


func _say(msg: String, ok: bool) -> void:
	last_msg = msg
	last_ok = ok
	if msg != "" and g != null and g.has_method("toast"):
		g.toast(msg)
	_notify()


func _notify() -> void:
	if changed.is_valid():
		changed.call()
