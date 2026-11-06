# NOVAGATE – Galaxy Gate düzeltmesi (yalnızca Galaxy Gate)

Klasör yapısı proje köküyle birebir aynı: dosyaları aynı yollarla kopyalayıp üzerine yaz.
`deploy.ps1` kökteki tüm `.gd` dosyalarını + `server/server_db.py`'yi yükleyip servisleri yeniden başlatıyor; ek adım yok.
Yeni tablolar (`player_gate_slots`, `player_gate_gen`) açılışta otomatik oluşur, mevcut veriye dokunulmaz.
Eski sistemde toplanmış parçalar ilk `gate_info` çağrısında yuvalara çevrilir (kaybolmaz).

## Değişen dosyalar
| Dosya | Ne değişti |
|---|---|
| `server/server_db.py` | Yeni jeneratör (`gate_generator_pulse`, `gate_generator_arm`), parça YUVALARI (`player_gate_slots`), jeneratör durumu (`player_gate_gen`); `gate_info` yuva + çarpan döndürür; `gate_activate`/`gate_finish` yuva tabanlı. Eski hatalı jeneratör (tüm kapılara +1 parça veriyor, Uridium düşmüyor, dispatcher'da yoktu) ve NPC'den parça (`gate_add_part`) SİLİNDİ |
| `net_server.gd` | NPC öldürünce parça düşmesi (`_gate_roll_part`) kaldırıldı; `gg_pulse` / `gg_arm` olayları; `gg_info` yuva + çarpan taşır. Sonuç `s_event` kanalıyla gider (eski kod tanımsız bir RPC çağırıyordu) |
| `net_game.gd` | `gg_pulse_result` istemciye yönlendirilir (eskiden hiç yönlendirilmiyordu), `gg_part` kaldırıldı |
| `main.gd` | Sağ üstteki bağımsız "GALAXY GENERATOR" paneli ve değişkenleri silindi; menü için `gate_pulse()`, `gate_arm()`, sonuç işleme |
| `control_panel.gd` | Mevcut Galaxy Gates menüsüne jeneratör (ÇEVİR, çarpan x2–x6, son sonuç, ihtimaller), parça yuvası ızgarası, kapı listesinde parça/durum |
| `data.gd` | `GATE_PART_CHANCE` (NPC'den %13) kaldırıldı; menü gösterimi için `GATE_GEN_*`, `GATE_MULT_MAX` |
| `server/test_gate_db.py` | Yeni DB testi |
| `KAPI_KURULUM.md` | Akış güncellendi |

Dokunulmadı: kapı dalgaları, NPC'ler, kapı ödülleri, kapıya giriş / ilerleme / ödül akışı.

## Uygulanan kurallar (orijinal DarkOrbit)
- Tek ortak jeneratör (Alfa/Beta/Gamma), **100 Uridium / çevirme**.
- Ödül tablosu: cephane %67, kapı parçası %13, xenomit %12, nano hull %4, tamir kuponu %3, log disk %1.
- Parça gerekleri: Alfa 34, Beta 48, Gamma 82.
- Parça çıkınca rastgele bir kapı ve o kapının rastgele bir yuvası seçilir. Yuva boşsa parça eklenir; doluysa (**tekrarlanan parça**) çarpana dönüşür: x2, x3, x4, x5, x6.
- Çarpan menüden istenen zaman "kullan" işaretlenir; bir sonraki çevirmenin ödülünü katlar ve harcanır. Parça ödülü katlanırsa o kapının eksik yuvalarına çarpan kadar parça yazılır; eksik yuva kalmadıysa artan her parça cephane olur.
- x6 doluyken yine tekrarlanan parça gelirse x6 otomatik kullanılır ve sıfırlanır.
- Tüm yuvalar dolunca menüdeki **KAPIYI AKTİF ET**, ardından şirketin X-1 haritasında kapının yanında J ile giriş. Kapı tamamlanınca parçalar sıfırlanır (mevcut davranış).

## Varsayımlar (kaynaklarda net olmayan noktalar) — `server/server_db.py` başından ayarlanır
- Çevirme başına ödül miktarları: cephane rastgele LCB-10 ×1000 / MCB-25 ×300 / MCB-50 ×150 / UCB-100 ×50; xenomit ×25; diğerleri ×1. Orijinal miktarları bulamadım; Uridium ekonomisini bozmayacak değerler seçtim.
- Parça için kapı seçimi eşit ihtimalli (1/3), sonra o kapının yuvası eşit ihtimalli.
- Nano Hull envantere `nano_hull` olarak yazılır; oyunda henüz kullanım işlevi yok.

## Test adımları
1. Sunucuda: `cd /opt/novagate/server && python3 test_gate_db.py` → `SONUC: HEPSI GECTI`.
2. Oyuna gir → Galaxy Gates menüsü: sağ üstte jeneratör paneli OLMAMALI; Alfa/Beta/Gamma soldan seçilebilmeli; parçalar 0/34, 0/48, 0/82.
3. ÇEVİR: Uridium 100 düşer, sonuç "Son çevirme" satırında ve toast'ta görünür. 99 Uridium ile buton pasif.
4. Parça çıkınca ilgili kapının karesi dolar, sayı artar. Tekrar çıkınca "tekrarlanan parça → çarpan x2", sonra x3…
5. "x? ÇARPANI KULLAN" → buton "SIRADAKİ ÇEVİRMEDE KULLANILACAK" olur; çevirince ödül katlanır, çarpan sıfırlanır.
6. Bir kapıyı tamamla (hızlı test için `player_gate_slots` tablosuna yuvaları ekleyebilirsin) → **KAPIYI AKTİF ET** aktifleşir → X-1'de kapının yanında J ile giriş.
7. NPC öldür → hiçbir kapı parçası düşmemeli.
8. Çık-gir: parçalar ve çarpan korunmalı.

## Not
Bu ortamda Godot yoktu; GDScript dosyaları derlenip çalıştırılmadı (girinti ve sözdizimi elle gözden geçirildi). Python/DB tarafı çalıştırılarak test edildi. İlk açılışta Godot hata verirse çıktıyı gönder.
