# Galaxy Gate - yeni kat akışı

Dosyaları proje köküne aynı adlarla kopyala (üzerine yaz). Ek DB değişikliği yok.
Sonra `deploy.ps1` çalıştır ve istemciyi yeniden export et (main.gd / net_game.gd / data.gd istemciyi de etkiler).

## Davranış
1. Kapıya girince oyuncu HER ZAMAN haritanın ortasında doğar. Kapı içinde sabit kapı YOKTUR (dalgalar bitmeden görünmez).
2. 5 sn hazırlık -> 1. dalga. Her dalga, bir öncekinin doğuşundan 5 sn sonra gelir (öldürmene bakmaz).
3. Her dalgada NPC'ler oyuncunun etrafında geniş (1700 birim yarıçaplı), eşit aralıklı bir daire olarak doğar ve üstüne gelir.
4. Kapı NPC'leri mesafeye ve senin ateş edip etmediğine bakmadan sana saldırır.
5. Tüm dalgalar doğup hepsi ölünce kat biter ve ORTADA iki kapı açılır:
   - sol: X-1 (girdiğin haritaya dönüş)
   - sağ: sonraki kat (ortaya alınırsın, yeni kat 5 sn sonra başlar)
6. Son katta ödül OTOMATİK yazılır ve yalnızca X-1 kapısı açılır. J ile girince X-1'e dönersin.
7. Ara katta X-1 kapısından çıkarsan ilerleme kayıtlıdır: tekrar girince kaldığın katın başından devam edersin.

## Değişenler
- data.gd: gate_map'ten sabit dönüş kapısı kaldırıldı (portals = []).
- net_server.gd: ortada doğuş, daire dizilimi, 5 sn dalga zamanlayıcısı, kat bitişi, kapı açma (`gg_gates`), sonraki kat (`@next`), NPC'lerin her zaman saldırması.
- net_game.gd: `gg_gates`, `gg_next` olayları istemciye yönlendirilir.
- main.gd: kapıları dinamik çizme/kapatma, sonraki kata geçiş, HUD ve bildirim metinleri (Bölüm -> Kat, Grup -> Dalga), dönüşte kapı noktasında belirme.

## Ayarlar (net_server.gd başı)
GATE_INTRO_SEC (5) · GATE_GROUP_GAP (5) · GATE_CIRCLE_R (1700) · GATE_EXIT_DX (500)

## Not
Godot bu ortamda yoktu; GDScript derlenip çalıştırılmadı. İlk açılışta hata verirse çıktıyı gönder.
Eski "bölüm sonu seçim penceresi" artık tetiklenmiyor (kod duruyor, zararsız).

## Ek değişiklikler (2. tur)
- Kapı içinde bonus kutu yok (`_spawn_world_boxes` gate haritasında kutu doğurmaz).
- Kapı içinde nükleer, NPC'lerin maksimum canının %50'sini vurur (normal haritalarda %15 kalır). Sunucu doğrulaması da %50'ye göre (`SV_NUKE_FRAC_GATE`, `NUKE_FRAC_GATE`).
- Kapı NPC'leri can/kalkan DOLDURAMAZ (yenilenme yalnızca Cubikon'daydı; kapı NPC'leri için açıkça kapatıldı).
- NPC lazer menzili oyuncununkinin %80'i: `DOData.NPC_LASER_RANGE_FRAC = 0.8` (data.gd). Oyuncu 700 -> NPC 560. Hem normal haritalarda hem kapıda, sunucuda ve tek oyunculu istemci kodunda geçerli; Protegit/Cubikon koruyucuları da bu menzile bağlandı.
- Değişen ek dosya: extras.gd (5 dosya: data.gd, net_server.gd, net_game.gd, main.gd, extras.gd)

## Ek değişiklik (3. tur)
- Her dalga bir öncekinden daha uzakta doğar: yarıçap = GATE_CIRCLE_R + GATE_CIRCLE_STEP x (dalga sırası). Varsayılan 1700 -> 2200 -> 2700 -> 3200 (DO birimi). Kat başında sıfırlanır. Ayar: net_server.gd başı.

## Ek değişiklik (4. tur)
- Galaxy Gate NPC'lerinin lazer menzili oyuncununkinin %50'sine indirildi (700 -> 350 DO birimi; yaklaşma mesafesi de buna bağlı olarak 210'a düştü). Kapı dışındaki NPC'ler %80'de kalır. Ayar: data.gd GATE_NPC_LASER_RANGE_FRAC.
