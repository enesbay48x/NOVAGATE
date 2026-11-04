# NOVAGATE – Gemi kalıcılığı, Combat Logout, Savaş kısıtları

Klasör yapısı proje köküyle birebir aynı: dosyaları aynı yollarla kopyalayıp üzerine yaz.
`deploy.ps1` zaten kökteki tüm `.gd` dosyalarını + `server/server_db.py`'yi yükleyip servisleri yeniden başlatıyor; ek bir adım gerekmiyor.

## Değişen dosyalar (8)
| Dosya | Ne değişti |
|---|---|
| `server/server_db.py` | `save_active_ship` komut dağıtıcıya EKLENDİ (Phoenix hatasının kök nedeni); yeni `save_loadout`, `save_selected_ammo`; girişte kayıtlı gemi/ekipman yükleme |
| `net_server.gd` | Combat Logout (hayalet gemi), sunucu doğrulamalı gemi değişimi / mühimmat / ekipman kaydı, yeniden bağlanınca devralma |
| `net.gd` | Yeni RPC'ler: `c_save_loadout`, `s_loadout_result`, `s_ship_result`; kopma tespiti (peer timeout) |
| `net_game.gd` | Sonuç yönlendirmeleri (`on_select_ammo_result` burada hiç yoktu → çağrı hata veriyordu) |
| `main.gd` | Gemi değişimi sunucu onayıyla; ekipman senkronu; yeniden bağlanınca can/kalkan devralma |
| `hud_do.gd` | "Roketler" kategorisi (roket değiştirme UI) kaldırıldı |
| `data.gd` | Tüm süreler tek yerde (aşağıda) |
| `server/test_loadout_persist.py` | YENİ: veritabanı testi (17 kontrol) |

`patches/` klasöründe her dosyanın farkı (diff) var.

## Kök neden (Görev 1)
1. `net_server.gd` `save_active_ship` çağırıyordu ama `server_db.py` komut dağıtıcısında bu komut yoktu → kayıt hiç yazılmıyordu → girişte hep Phoenix.
2. Ekipman (lazer/kalkan/jeneratör/droid/konfig) için sunucuya kayıt yolu hiç yoktu (`player_loads` tablosu vardı ama kimse yazmıyordu).

## Görev 1 – Kalıcılık
- Gemi seçimi: istemci `c_ship` ister → sunucu doğrular (sahiplik, police=admin) → DB'ye yazar → `s_ship_result` ile bildirir. DB yazılamazsa değişiklik uygulanmaz.
- Ekipman: istemcide her ekipman değişikliği `save_game()` çağırdığı için tek noktadan (`_sync_loadout`) `c_save_loadout` gider. Sunucu listeyi katalog + gemi yuva sayısı + envantere göre SÜZER ve süzülmüş hali geri yollar; istemci farklıysa onu uygular.
- Giriş: DB'deki aktif gemi + ekipman yüklenir; kayıt yoksa (yeni oyuncu) Phoenix verilir; kayıtlı gemi artık hesapta değilse Phoenix'e döner.

## Görev 2 – Combat Logout (sunucu kontrollü)
- Bağlantı kopunca (istemci kapanması, internet kopması, kick) gemi silinmez: aynı `players` kaydında `ghost=true` olur. Haritada görünür, NPC ve oyuncular saldırabilir, harita/NPC'ler boşalmaz.
- Süre: savaş dışı 15 sn, NPC saldırısı 30 sn, PvP 30 sn. Hasar alırsa süre yenilenir.
- Hayalet gemi hasarı sunucuda işlenir (kalkan sonra can); can 0 olursa normal ölüm akışı (kill mesajı, PvP ödülü, patlama = `s_pleave`), yeniden girişte ev üssünde doğar.
- Süre dolunca gemi kaldırılır ve konum kaydedilir.
- Süre dolmadan tekrar bağlanan oyuncu aynı harita/konum/can/kalkanla devam eder (konum sunucudan gelir, istemci ışınlanamaz).
- Kopmanın sunucuda anlaşılma süresi `NET_PEER_TIMEOUT_MAX_MS` (10 sn) ile sınırlandı (ENet varsayılanı ~30 sn).

## Görev 3 – Kısıtlar (hepsi sunucuda)
- Savaşta gemi/hangar değiştirme: `on_ship` reddeder (savaş = saldırdı/saldırıldı/hasar aldı son 10 sn).
- Hasar alırken lazer mühimmatı değiştirme: `on_select_ammo` reddeder (son hasardan 5 sn).
- Konfigürasyon değiştirme serbest (kontrol yok, sadece kayıt).
- Roket değiştirme: HUD'daki "Roketler" kategorisi kaldırıldı. Sunucuda roket seçme kodu hiç yoktu (`c_select_ammo` lazer mühimmatı içindir), temizlenecek bir şey çıkmadı. R tuşu ile roket atışı ve mobil ROKET düğmesi KORUNDU.

## Ayarlanabilir sabitler (`data.gd`)
`COMBAT_LOGOUT_SAFE_SEC=15`, `COMBAT_LOGOUT_NPC_SEC=30`, `COMBAT_LOGOUT_PVP_SEC=30`, `AMMO_SWITCH_LOCK_SEC=5`, `GHOST_SHIELD_ABSORB=0.8`, `NET_PEER_TIMEOUT_MAX_MS=10000` (savaş sayacı: mevcut `COMBAT_SEC`, `AGGRESSOR_LOCK_SEC`).

## Önemli
- RPC listesi değişti → **oyunu yeniden export et**; eski istemci yeni sunucuyla çalışmaz.
- Godot bu ortamda yoktu: GDScript çalıştırılamadı, yalnızca girinti/parantez denetimi yapıldı. DB tarafı gerçek SQLite ile test edildi (17/17 geçti). Bu yüzden aşağıdaki testleri deploy sonrası çalıştır.
- Kapsam dışı kalan/varsayım: formasyon satın alımları sunucuya kaydedilmiyor (mevcut durum), bu yüzden formasyon yalnızca geçerli kod mu diye doğrulanıyor. Hayalet gemide kalkan emilimi sabit orana (0.8) bağlı; canlı oyuncuda jeneratöre göre değişir.
- Paketi zip'e dahil etme: `opencode.json` (açık API anahtarı), `admin_password.txt`, `auth_key.pem` projede duruyor; bunları paylaşma/yedekleme.

## Test adımları
**Sunucu (DB):** `cd server && python3 test_loadout_persist.py` → `HEPSI GECTI`.
**Deploy sonrası log:** `journalctl -u novagate-server -n 100` içinde `SCRIPT ERROR / Parse Error` olmamalı.
1. Phoenix hatası: hesapla gir, hangardan başka gemi seç, lazer/jeneratör tak-çıkar, konfig değiştir → oyundan çık, tekrar gir: seçili gemi ve ekipmanlar aynı gelmeli. Yeni hesap: Phoenix.
2. Savaş dışı çıkış: pencereyi kapat → log `[COMBAT LOGOUT] ... sure=15 sn`; ikinci hesapla haritada gemi 15 sn görünür, sonra kaybolur.
3. NPC altında çıkış: NPC'ye saldırırken kapat → `sure=30 sn`; gemi hasar yer, her hasarda sayaç 30'a döner. Can 0 olursa patlar.
4. PvP: iki hesap karşı şirketlerde; biri vurulurken kapatır → 30 sn, saldırgan gemiyi vurabilir/öldürebilir (kill mesajı).
5. Süre dolmadan tekrar giriş: aynı harita/konum, can/kalkan kaldığı gibi; log `gemi mevcut durumuyla devralindi`.
6. İnternet kopması: istemci ağını kes → ~10 sn sonra aynı kurallar.
7. Savaşta (NPC'ye ateş ederken) hangardan başka gemi seç → "Savaşta gemi/hangar değiştirilemez", gemi değişmez. Savaş dışında değişir.
8. Hasar alırken (NPC ateşi altında) mühimmat değiştir → reddedilir; 5 sn sonra serbest. Konfig (C tuşu) savaşta serbest.
9. Alt çubukta "Roketler" kategorisi yok; R tuşu hâlâ roket atıyor.
