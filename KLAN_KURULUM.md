# NOVAGATE – Klan Sistemi

Bu klasör, projenin kök dizinine (project.godot'un olduğu yer) aynı klasör yapısıyla kopyalanır. `deploy.ps1` kökteki tüm `.gd` dosyalarını ve `server/server_db.py` dosyasını zaten sunucuya yüklüyor.

## Değişen / eklenen dosyalar
| Dosya | Ne yapıyor |
|---|---|
| `clan_client.gd` (YENİ) | İstemci klan durumu: klanım, üyeler, davetler, başvurular, arama listesi, haritadaki klan etiketleri |
| `server/server_db.py` | Klan tabloları (otomatik oluşur) + `clan_op` kuralları, `clan_tag_of`, şirket değiştirmede klan kontrolü |
| `net_server.gd` | Giriş anında klan yükleme, klan olayları, klan sohbeti, genel sohbette `[TAG] nick` |
| `net_game.gd` | Klan olaylarını `clan_client.gd`'ye yönlendirir, yeni gelen oyuncuya etiket uygular |
| `control_panel.gd` | KLAN sekmesi (eski kapalı sayfa yerine tam menü) |
| `main.gd` | İsim plakasında `[TAG]` (kendi plaka + uzak oyuncular) |
| `hud_do.gd` | Sohbet penceresine KLAN sekmesi (yalnızca klandayken görünür) |
| `minimap.gd` | Klan üyeleri yeşil nokta + alt şeritte "Klan N" göstergesi |

RPC listesi değişmedi, `PROTO` aynı (genel olay kanalı kullanıldı). Eski istemciler yine bağlanır; klan menüsünü ve sekmeyi görmezler, genel sohbette `[TAG] nick` görürler.

## Kurallar
- Klan adı 3–20 karakter, etiket 2–4 harf/rakam (otomatik büyük harf). Ad ve etiket tekil.
- Bir hesap tek klanda. Klanlar şirkete bağlı: yalnızca aynı şirketin oyuncuları katılır/başvurur. Klandayken şirket değiştirilemez.
- En fazla 50 üye, aynı anda en fazla 5 başvuru.
- Roller: **Lider** (rütbe verme, liderlik devri, açıklama, klanı dağıtma, üye çıkarma), **Subay** (davet, başvuru kabul/ret, üye çıkarma), **Üye**.
- Lider, başka üye varken ayrılamaz; önce devreder veya klanı dağıtır.
- Klan kurma bedeli `server_db.py` içinde `CLAN_CREATE_COST_CR` (şu an 0 = ücretsiz). Üye sınırı `CLAN_MAX_MEMBERS`.
- Her şey sunucuda doğrulanır; istemciden gelen veri güvenilmez kabul edilir.

## Kurulum
1. Projeyi yedekle, klasördeki dosyaları aynı yollara kopyala (üzerine yaz).
2. `deploy.ps1` çalıştır (veya opencode ile yükle).
3. DB köprüsünü (`server_db.py`) ve Godot oyun sunucusunu yeniden başlat. Klan tabloları ilk açılışta kendiliğinden oluşur.
4. Oyunu yeniden export et (klan menüsü yeni istemci ister).

## Test adımları
1. Aynı şirketten iki hesap (A, B) ve başka şirketten bir hesap (C) ile gir.
2. A: Kontrol Paneli → Klan → KLAN KUR (ad: `DARK LEGION`, etiket: `DL`). Plakada `[DL] A` görünmeli, sohbet penceresinde KLAN sekmesi açılmalı.
3. B: Klan Listesi → BAŞVUR. A: BAŞVURULAR → KABUL ET. B'de üye görünümü açılmalı. Alternatif: A, B'yi nick ile davet eder; B DAVETLER sekmesinden kabul eder.
4. İkisi aynı haritadayken: birbirlerinin plakasında yeşil `[DL]`, minimap'te yeşil nokta ve "Klan 1" yazısı.
5. KLAN sekmesinde yaz: yalnızca A ve B görür. C ne klanı ne mesajı görür, C'nin klan listesinde `DL` çıkmaz.
6. Lider: SUBAY YAP, LİDER YAP, ÇIKAR (iki adımlı onay). Üye: KLANDAN AYRIL. Lider tek başınayken: AYRIL VE KLANI KAPAT.
7. Klandayken şirket değiştirmeyi dene: engellenmeli.

## Notlar
- Godot sandbox'ta çalıştırılamadığı için GDScript tarafı yalnızca kod incelemesiyle kontrol edildi. Sunucu DB mantığı (kur, başvur, davet, kabul, rütbe, devir, çıkar, ayrıl, dağıt) otomatik testle doğrulandı. Godot'ta açınca bir parse hatası çıkarsa satırı gönder, hemen düzeltirim.
- `minimap_do.gd` kullanılmıyor (oyun `minimap.gd`'yi yüklüyor), dokunulmadı.
- Zip içinde `admin_password.txt` ve `auth_key.pem` vardı; bunları paylaşmamanı, mümkünse yenilemeni öneririm.
