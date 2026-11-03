# Task 1 - Tek cihaz kuralı: doğrulama listesi

Python tarafı (test_session_lock.py) sqlite üzerinde gerçekten çalıştırıldı: 11/11 geçti
(devralma, eski oturum renew=False, eski release yeni kilidi silmez, çökme sonrası bayat kilit
girişi engellemez, 25 eşzamanlı giriş yarışında tam 1 sahip).

GDScript tarafı Godot olmadan test edilemedi. OpenCode'da sırayla:
1. `godot --headless --check-only` (veya proje açılışı) -> script hatası yok.
2. RPC listesi değişmedi: `git diff` içinde `@rpc` satırı eklenmemiş/silinmemiş olmalı
   (yeni RPC yok; kick için mevcut `s_disconnect` kullanılıyor).
3. Aynı hesapla iki bağlantı: A girer, B girer -> A'da "Hesabına başka bir cihazdan girildi"
   görünür ve bağlantı kopar, B oyunda kalır. Sunucu logunda "Eski oturum dusuruluyor" satırı.
4. A'nın konumu B'nin ilk yüklemesinde görünür (kick -> kayıt -> yükleme sırası).
5. B 100 sn oyunda kalır -> kilit düşmez (heartbeat 30 sn).
6. Sunucu yeniden başlat, hemen giriş yap -> "başka oturumda" hatası YOK.
