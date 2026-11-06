# Galaxy Gates: parça, aktivasyon, kayıt (NovaGate)

## Değişen dosyalar (proje kök klasörüne üzerine yaz)
- data.gd          : kapı tablosu (x1/x2/x3, 34/48/82 parça, ödüller), %13 parça şansı, X-1 kapı noktaları
- net_server.gd    : parça düşmesi, aktivasyon, kapı girişi doğrulaması, ilerleme kaydı/devam, bölüm sonu seçimi
- net_game.gd      : yeni olay tipleri (gg_info, gg_part, gg_activated, gg_return)
- main.gd          : X-1'de kapıların çizimi, J ile giriş, ipucu, bölüm sonu seçim penceresi
- control_panel.gd : Galaxy Gates sayfası (parça çubuğu, "KAPIYI AKTİF ET")
- server/server_db.py : tablolar player_gate_parts / player_gate_progress + gate_* metodları
- server/test_gate_db.py : DB katmanı testi (python3 test_gate_db.py)

## Kurulum
1. Yedek al. 2. Dosyaları üzerine yaz. 3. deploy.ps1 çalıştır (server_db.py yeniden başlar; yeni tablolar
   açılışta otomatik oluşur, mevcut veriye dokunulmaz). 4. İstemciyi yeniden export et (main.gd/net_game.gd değişti).

## Akış
NPC öldür -> %13 parça (sıra Alfa, Beta, Gamma) -> parçalar tamamlanınca Galaxy Gates sayfasında "KAPIYI AKTİF ET"
-> şirketinin X-1 haritasında kapının yanında J -> 10 bölüm x 4 dalga -> her bölüm sonunda
"Sonraki bölüm / Ana haritaya dön" -> son bölüm bitince ödül (Uridium, UCB-100, TP, şeref, ...).

## Ayarlar (data.gd)
GATE_PART_CHANCE (0.13) · GATE_REBUILD_AFTER_COMPLETE (true: tamamlayınca kapı yeniden kurulur) ·
GATE_ENTER_RANGE · GATE_SITE_* (kapı konumları) · GALAXY_GATES.*.parts / mul / reward
