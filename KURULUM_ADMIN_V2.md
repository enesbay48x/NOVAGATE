# NovaGate Admin Paneli v2 – Kurulum

Değişen dosyalar (hepsi `/home/claude/out` içinde):

| Dosya | Nereye | Ne yapıyor |
|---|---|---|
| `admin/admin_panel.py` | `/opt/novagate/admin/admin_panel.py` | Yeni panel (arayüz + tüm sayfalar) |
| `server/server_db.py` | `/opt/novagate/server/server_db.py` | `company_events` tablosu, `get_active_events`, `record_event_bonus` |
| `net_server.gd` | `/opt/novagate/net_server.gd` | Bonusu NPC / Cubikon / PvP ödülüne uygular |
| `nginx_novagate.conf` | `/etc/nginx/sites-available/...` | (Opsiyonel) IP kısıtı satırları eklendi |

İstemci (oyun uygulaması) **değişmiyor**, yeni RPC eklenmedi; telefona yeni sürüm göndermeye gerek yok.

## Adımlar

1. **Yedek al** (DEPLOY_YEDEK.txt'deki komutlar):
   `sqlite3 /opt/novagate/server/novagate_game.db ".backup '/opt/novagate/server/backups/onceki.db.bak'"`
   Aynısını `novagate_auth.db` için de yap.
2. Dosyaları yukarıdaki yerlere yükle. Panel dosyasını yüklerken sahibi `novagate` kalsın:
   `sudo chown novagate:novagate /opt/novagate/admin/admin_panel.py`
3. Panelin Python ortamında `argon2-cffi` ve `flask` kurulu olmalı:
   `sudo /opt/novagate/admin/venv/bin/pip install flask argon2-cffi`
   (argon2 yoksa panel güvenlik için girişi kapalı tutar.)
4. Servisleri yeniden başlat:
   `sudo systemctl restart novagate-admin-panel novagate-db novagate-server`
5. Panele gir → **Etkinlikler** sayfasından deneme etkinliği başlat (ör. %50 bonus, 30 dk), o şirketten bir hesapla NPC kes, ödülün arttığını kontrol et, sonra **Bitir**.
6. `nginx_novagate.conf` içindeki `allow` / `deny` satırlarına kendi IP'ni yazıp `sudo nginx -t && sudo systemctl reload nginx`.

## Etkinlik nasıl çalışır
- Çarpan = 1 + bonus%/100. **+%300 → ödül 4 katı.** 3 katı istiyorsan +%200 gir. Formda canlı önizleme var.
- Sadece seçilen şirketin oyuncusunun **kendi** öldürdüğü NPC/oyuncudan gelen ödül artar. Grup ödülünde her üye kendi şirketine göre hesaplanır.
- PvP ödülü oyunda Onur'dur. NPC için Kredi / Uridium / Deneyim / Onur (Seprom, uridiuma bağlı olduğu için onunla birlikte artar).
- Sonuç DB'nin ödül üst sınırlarını aşmaz. Etkinlik süresi sunucu saatine göre biter; panel kapalı olsa da çalışır. Başlama/bitiş sunucuya en fazla ~5 sn gecikmeyle yansır.
- Aynı şirket için aynı anda iki etkinlik başlatılamaz.
