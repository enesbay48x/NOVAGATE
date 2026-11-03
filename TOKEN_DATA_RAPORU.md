# Rapor: Oyuncu verisi kayıt/yükleme tutarsızlığı — Araştırma

**Tarih:** 3 Kasım 2026  
**Kural:** Hiçbir dosya değiştirilmedi. Sadece okunup raporlandı.

Hesap: "asdasd", account_id=1

## BELİRTİ ÖZETİ
- Çıkışta: Police, HP 500.000, config "LF-4 x50", ammo dolu (3186, 400k, 500k)
- Tekrar giriş: Police ama ammo hepsi 0
- Atılmadan sonra giriş: Phoenix, HP 10.000, config "LF-4 x2", ammo dolu → DB'deki gerçek kayıt Phoenix; Police sadece ghost'ta (sunucu hafızasında) yaşıyordu

---

## 1. HANGİ `net_server.gd` AWS'DE ÇALIŞIYOR?

`deploy.ps1` (satır 50): `$EXCLUDE = @("net_server_from_server.gd", ...)` → kökteki `net_server.gd` yüklenir, `server/net_server_from_server.py` değil.  
AWS'de (`/opt/novagate/net_server.gd`):
- `save_active_ship`: 1 kez var
- `ghost_players`: 11 kez var
- `_session_hash`: 6 kez var

Sonuç: **AWS'de kökteki yeni `net_server.gd` çalışıyor.** `server/net_server.gd` eski/kullanılmıyor.

---

## 2. GHOST GERİ YÜKLEME SORUNU (`net_server.gd:266-321`)

`on_attach_token` içinde ghost'tan geri yüklenirken (`gp != null` bloğu):

```gd
var ps_json: Dictionary = {
    "callsign": str(gp_p.get("name", "Gezgin")),
    "faction": int(gp_p.get("faction", 1)),
    "ship": str(gp_p.get("ship", "phoenix")),
    "map": str(gp_p.get("map", "")),
    "px": float(gp_p.get("px", 0.0)),    # <-- SORUN: ghost p'de "px"/"pz" yok, sadece "pos" (Vector3) var
    "pz": float(gp_p.get("pz", 0.0)),    # --> her zaman 0.0 döner
    ...
    "form": str(gp_p.get("form", "std")),
    "drn": ...,
    "owned": ...,
    "cr": ...,
    ...
    "loads": gp_p.get("loads", {}),
    "cfgi": int(gp_p.get("cfgi", 0)),
}
```

**Eksik alanlar (JSON'a yazılmıyor, istemciye gitmiyor):**
- `ammo` (mermi slotları)
- `rockets` (roket sayısı)
- `skill_points`
- `maps_visited`
- `drone_equip`
- `selected_ammo`
- `px`/`pz` (ghost `pos` Vector3'i var ama `px`/`pz` anahtarı yok → 0.0)

İstemci `main.gd:_on_attach_result` (~1916-1973) bu JSON'dan `SV`'yi kuruyor. Eksik alanlar varsayılan değerle dolduruluyor → ammo 0, ship Phoenix (DB'den), config sıfırlanıyor.

---

## 3. `_SESSION_HASH` GÜNCellenmiyor → ATILMA NEDENİ

Ghost'tan geri yüklendiğinde (`players[peer_id] = gp.p`):

- `gp.p` içinde eski `_session_hash` var (önceki oturumun hash'i)
- Yeni `session_hash` (şu anki token'dan gelen) players dict'e **yazılmıyor**
- Sonraki `tick` (30 sn'de bir, `renew_session_lock`) bu eski hash ile çağrılır → `owned=false` → `_kick_session("Hesabına başka bir cihazdan girildi")`

`server_db.py:renew_session_lock` (satır 974-998): `UPDATE ... WHERE session_token = ?` → eski hash eşleşmez → `rowcount = 0` → `owned=False` → sunucu oyuncuyu atar.

---

## KÖK NEDEN (kısmi, 1-3. adım)

1. Ghost JSON'u `px`/`pz` yerine `pos.x`/`pos.z` okumamalı; eksik alanları DB'den tamalamalı.
2. Ghost geri yüklemesinde yeni `session_hash` ayarlanmamalıdır, aksi taktirde sonraki heartbeat `owned=false` döner ve oyuncu atılır.

---

## 4. KONFİGÜRASYON: `loads` / `cfg_index` / `selected_ammo`

Ghost JSON'da `loads` ve `cfgi` var, ancak `selected_ammo` yok (`sel` alanı yok).  
İstemci `main.gd:_on_attach_result` (~1933): `"sel": str(ps.get("selected_ammo", "x1"))` → `selected_ammo` anahtarı JSON'da yoksa `"x1"` varsayılanı.  
Ghost'tan gelen `loads`/`cfgi` var ama `selected_ammo` yok → config sıfırlanıyor ("LF-4 x50" yerine "LF-4 x2" gibi).

## 5. ATILMA NEDENİ: İSTEMCİ `s_disconnect`

`net.gd:527-537`:
```gd
func s_disconnect(reason: String) -> void:
    if is_server: return
    last_error = reason
    online = false
    ...
    if game != null and is_instance_valid(game):
        game.net_lost()
```
`reason` zaten `last_error`'ye yazılıyor ama `main.gd`'de `net_lost()` nasıl gösteriliyor bilinen değil. Atılma sebebi ekranda görünmüyor olabilir (`lbl_auth_msg` veya `menu` ile gösterilmiyor).

---

## KÖK NEDEN (kanıtlanmış)

1. **Ghost `px`/`pz` = 0.0**: ghost `p` içinde konum `pos` (Vector3) olarak saklanır, `px`/`pz` anahtarı yok. JSON'da `0.0` dönüyor → istemci konumu sıfırlanıyor.
2. **Eksik JSON alanları**: `ammo`, `rockets`, `skill_points`, `maps_visited`, `drone_equip`, `selected_ammo` ghost'tan dönmüyor → istemci varsayılanlarla dolduruyor (ammo=0, ship=Phoenix, config=x1).
3. **`_session_hash` güncellenmiyor**: Ghost'tan geri yüklendiğinde yeni `session_hash` players dict'e yazılmıyor. Sonraki 30 sn'lik `renew_session_lock` heartbeat eski hash ile çalışır → `owned=false` → `_kick_session("Hesabına başka bir cihazdan girildi")`.

---

## ÖNERİLEN DÜZELME (uygulanmadı)

1. Ghost geri yüklemeden önce DB'den `load_player_state` yükle, sonra ghost'taki canlı alanları (map, konum, ship, hp, sh, form, drn) üstüne yaz. `px`/`pz` için `pos.x`/`pos.z` kullan.
2. Ghost JSON'una eksik alanları ekle: `ammo`, `rockets`, `skill_points`, `maps_visited`, `drone_equip`, `selected_ammo` (DB'den).
3. Ghost'tan geri yüklendiğinde `_session_hash`'ı yeni `session_hash`'a eşitle.
4. `save_active_ship` (on_ship içinde) zaten doğru ama DB yoksa yazılamıyor — DB servisi artık aktif (önceki rapor).
5. `s_disconnect` reason'unu `main.gd`'de `lbl_auth_msg` ile göster.

Değiştirilecek dosya: `net_server.gd` (kök, AWS'de çalışan). `server/net_server.gd` dejavu, değiştirilmeyecek.

