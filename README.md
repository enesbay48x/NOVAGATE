# Gemi modelleri: yükseltme paketi

Bu pakette yalnızca **değişen** dosyalar var (84 adet .glb ve 91 adet .png). Dosyalar boyut nedeniyle 3 zip'e bölündü (`ship_upgrade_part1..3.zip`); üçünü de projenizin `models/` klasörüne çıkarın.

## Ne değişti

1. **Materyal (PBR) iyileştirme, 84 gemi.** Eski modellerde `metallicFactor = 0` olduğu için metalik doku hiç etki etmiyordu.
   Özellik (specular) haritasından gerçek bir roughness (G) ve metalik (B) kanalı üretildi. Metalik en fazla 0.55.
   Kristal ve organik modeller (kristallin, lordakia, curcubitor, hindi vb.) metalik almaz, yalnızca roughness ayarı yapılır.
2. **Emissive güçlendirme, 38 gemi.** Işıkları seyrek olan metal gemilerde `KHR_materials_emissive_strength = 1.6`.
3. **Eksik diffuse dokusu üretildi, 7 gemi:** aegis-veteran, goliath-double-winged, goliath-reversed-angled-wings, mimesis, pet-mirage, pet-pusat, tartarus.
   Bu gemiler GLB'de baseColor dokusu olmadığı için düz beyaz görünüyordu. Üretilen doku, özellik/normal haritasından türetilmiş
   geçici bir gövde boyasıdır (ton, kardeş gemiden alındı). Elinizde gerçek diffuse varsa onunla değiştirin.
4. **Seyir ışıkları, 60 gemi:** sol kanat ucu kırmızı, sağ kanat ucu yeşil, kıçta beyaz. Tek bir ek düğüm: `addon_navlights`.
   Beğenmezseniz sahnede bu düğümü silmeniz yeterli.

## Dokunulmayanlar
Mevcut hiçbir düğüm, mesh veya bağlantı noktası (`engine_*`, `laserpoint_*`, `light_position`) değiştirilmedi. Konumları birebir aynı.
Silah namlusu, anten ve motor memesi **eklenmedi**: ölçümde 310 silah noktasının 284'ü zaten modellenmiş namlu uçlarında duruyor.

Hiç dokusu olmayan veya gemi olmayan modeller olduğu gibi bırakıldı: aegis-repair-cross, aegis-repair-pod, aegis-ship-pod, bigboy, citadel, defcom, devolarium, kucurbium, sibelon-boss, sibelonit-boss-tentacles, streuner-seeker-rocket, binalar (building-*), asteroid/uydu, jumpgate, drone ve hitac-mothership.

## Kurulum
1. Projenizi yedekleyin.
2. Bu paketteki `models/` içeriğini projenizdeki `models/` klasörüne kopyalayıp üzerine yazın (.glb **ve** .png dosyaları birlikte).
   Projenizde dokular Godot tarafından dışarı çıkarılmış (extract) olduğundan PNG'leri de güncellemek şarttır.
3. Godot'u açın; dosyalar kendiliğinden yeniden içe aktarılır.

## Ayarlar
`tools/upgrade.py` içindeki sabitler: `METAL_MAX`, `ROUGH_MIN/MAX`, `EMISSIVE_STRENGTH`, `NAV_RADIUS_FRAC`.
Çalıştırma (Python 3, numpy ve Pillow gerekir): `python3 tools/upgrade.py <orijinal_models_klasoru> <cikti_klasoru>`
Sahnenizde gökyüzü/yansıma yoksa ve gemiler fazla koyu geliyorsa `METAL_MAX` değerini 0.3'e indirin.
