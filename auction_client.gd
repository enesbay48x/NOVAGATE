extends RefCounted
# NOVAGATE - ACIK ARTIRMA ISTEMCI TARAFI
# Sunucudan gelen anlik goruntuyu (lots / hist) tutar; teklif ve "Hemen Al" isteklerini gonderir.
# Para akisi:  teklif -> bakiyeden DUS (emanet) -> sunucuya bildir -> sunucu kabul/ret eder
#              ret ya da gecilme -> sunucu POSTA ile iade eder; kazanma -> POSTA ile esya gelir.
# Posta kaydi SV.auc_done'a yazilir; ayni posta iki kez uygulanmaz. Sunucuya ulasmayan islemler
# (SV.auc_pending) bir sonraki baglantida sunucuya sorulur, ulasmadiysa emanet geri verilir.

const DOData := preload("res://data.gd")
const DONE_KEEP := 300

var g                          # main.gd
var net: Node                  # Net autoload
var lots: Array = []
var hist: Array = []
var round_no: int = 0
var has_state: bool = false
var changed: Callable          # arayuz yenileme geri cagrisi
var _end_ms: int = 0
var _seq: int = 0
var _warned_cap: bool = false


func _init(main_node, net_node: Node) -> void:
	g = main_node
	net = net_node


# ------------------------------------------------------------------ durum
func remaining() -> int:
	if not has_state:
		return -1
	return maxi(0, ceili(float(_end_ms - Time.get_ticks_msec()) / 1000.0))


func find_lot(id: int) -> Dictionary:
	for l in lots:
		if int(l["id"]) == id:
			return l
	return {}


func min_bid(lot: Dictionary) -> int:
	if int(lot.get("bid", 0)) > 0:
		return int(lot["bid"]) + 1
	return int(lot.get("start", 1))


func on_state(snap: Dictionary) -> void:
	lots = snap.get("lots", [])
	hist = snap.get("hist", [])
	round_no = int(snap.get("round", 0))
	_end_ms = Time.get_ticks_msec() + int((int(snap.get("end", 0)) - int(snap.get("now", 0))) * 1000)
	has_state = true
	_emit()


func _emit() -> void:
	if changed.is_valid():
		changed.call()


func request_open() -> void:
	if net.online:
		net.rpc_id(1, "c_auc_open", _pending_ids())


func _pending() -> Dictionary:
	if g.SV.is_empty():
		return {}
	if not g.SV.has("auc_pending") or not (g.SV["auc_pending"] is Dictionary):
		g.SV["auc_pending"] = {}
	return g.SV["auc_pending"]


func _pending_ids() -> Array:
	var out: Array = []
	for k in _pending().keys():
		out.append(int(str(k)))
	return out


func _new_op() -> int:
	_seq = (_seq + 1) % 100
	return int(Time.get_unix_time_from_system() * 1000.0) * 100 + _seq


# ------------------------------------------------------------------ teklif / hemen al
func bid(lot_id: int, amount: int) -> void:
	if not net.online or g.SV.is_empty():
		g.toast("Açık artırma için sunucuya bağlı olmalısın.")
		return
	if bool(g.SV.get("free", false)):
		g.toast("Test parası modunda açık artırma kapalı (F9'u kapat).")
		return
	var lot: Dictionary = find_lot(lot_id)
	if lot.is_empty() or str(lot["state"]) != "open":
		g.toast("Bu açık artırma artık açık değil.")
		return
	if amount < min_bid(lot):
		g.toast("Teklif en az %s Kr olmalı." % g._n(float(min_bid(lot))))
		return
	var held: int = int(lot["bid"]) if bool(lot.get("mine", false)) else 0
	var need: int = amount - held
	if need <= 0:
		g.toast("Teklif mevcut teklifinden yüksek olmalı.")
		return
	if int(g.SV.cr) < need:
		g.toast("Yetersiz Kredi! Gerekli: %s Kr" % g._n(float(need)))
		return
	g.SV.cr = int(g.SV.cr) - need
	var op: int = _new_op()
	_pending()[str(op)] = {"cr": need, "uri": 0}
	g.save_game()
	net.rpc_id(1, "c_auc_bid", op, lot_id, amount, need)


func buy_now(lot_id: int) -> void:
	if not net.online or g.SV.is_empty():
		g.toast("Açık artırma için sunucuya bağlı olmalısın.")
		return
	if bool(g.SV.get("free", false)):
		g.toast("Test parası modunda açık artırma kapalı (F9'u kapat).")
		return
	var lot: Dictionary = find_lot(lot_id)
	if lot.is_empty() or str(lot["state"]) != "open":
		g.toast("Bu açık artırma artık açık değil.")
		return
	var price: int = int(lot["instant"])
	if int(g.SV.uri) < price:
		g.toast("Yetersiz Uridium! Gerekli: %s U" % g._n(float(price)))
		return
	g.SV.uri = int(g.SV.uri) - price
	var op: int = _new_op()
	_pending()[str(op)] = {"cr": 0, "uri": price}
	g.save_game()
	net.rpc_id(1, "c_auc_buy", op, lot_id, price)


# ------------------------------------------------------------------ sunucu yanitlari
func on_op(op: int, ok: bool, text: String) -> void:
	_pending().erase(str(op))
	g.save_game()
	if text != "":
		g.toast(text)
	_emit()


func on_resolve(known: Array, unknown: Array) -> void:
	var pend: Dictionary = _pending()
	for op in known:
		pend.erase(str(int(op)))
	var back_cr: int = 0
	var back_uri: int = 0
	for op in unknown:
		var p: Variant = pend.get(str(int(op)), null)
		if p is Dictionary:
			back_cr += int(p.get("cr", 0))
			back_uri += int(p.get("uri", 0))
		pend.erase(str(int(op)))
	if back_cr > 0 or back_uri > 0:
		g.SV.cr = int(g.SV.cr) + back_cr
		g.SV.uri = int(g.SV.uri) + back_uri
		g.toast("Sunucuya ulaşmayan işlem iade edildi: %s Kr, %s U" % [g._n(float(back_cr)), g._n(float(back_uri))])
	g.save_game()
	_emit()


func on_msg(text: String) -> void:
	g.toast(text)


func on_mail(arr: Array) -> void:
	if g.SV.is_empty():
		return
	var done: Array = g.SV.get("auc_done", [])
	var ack: Array = []
	var dirty := false
	for m in arr:
		var id: int = int(m.get("id", 0))
		if id <= 0:
			continue
		if _was_done(done, id):
			ack.append(id)
			continue
		var kind: String = str(m.get("kind", ""))
		var ok := true
		if kind == "refund":
			g.SV.cr = int(g.SV.cr) + int(m.get("cr", 0))
			g.SV.uri = int(g.SV.uri) + int(m.get("uri", 0))
		elif kind == "item":
			ok = _deliver(str(m.get("item", "")), int(m.get("qty", 1)), bool(m.get("granted", false)))
			if ok:
				g.toast(str(m.get("txt", "Açık artırma ödülü teslim edildi.")))
		if ok:
			done.append(id)
			ack.append(id)
			dirty = true
		elif not _warned_cap:
			_warned_cap = true
			g.toast("Açık artırma ödülün hazır ama envanterde yer yok (droid sınırı). Yer açınca otomatik teslim edilir.")
	while done.size() > DONE_KEEP:
		done.remove_at(0)
	g.SV["auc_done"] = done
	if dirty:
		g.save_game()          # once KAYDET, sonra sunucuya onayla
	if not ack.is_empty() and net.online:
		net.rpc_id(1, "c_auc_ack", ack)
	_emit()


func _was_done(done: Array, id: int) -> bool:
	for x in done:
		if int(x) == id:
			return true
	return false


# Esyayi envantere ekler. Eklenemezse false doner (posta sunucuda bekler, kaybolmaz).
func _deliver(item: String, qty: int, granted: bool = false) -> bool:
	if g.item_def(item).is_empty() or qty <= 0:
		g.toast("Açık artırma ödülü tanınmadı (%s); atlandı." % item)
		push_warning("Açık artırma ürünü tanınmadı: %s" % item)
		return true
	# Sunucu urunu zaten kendi envanterine yazdi (granted): burada yalnizca yerel gorunumu esitle.
	# Sunucu yazmadiysa (eski posta) yerel envantere EKLEME: sunucu envanteri belirleyici, ekipmana giremez.
	if not granted:
		return false
	if DOData.DRONES.has(item) and g.drones_owned() + qty > DOData.MAX_DRONES:
		return true   # sunucu kapasiteyi zaten dogruladi; yerel sayac sapmasin diye atla (giriste esitlenir)
	g.inv_dict(item)[item] = g.inv_count(item) + qty
	return true
