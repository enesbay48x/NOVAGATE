# Galaxy Gate halkaları + sunucu sıralaması (rütbe / ilk 10)

Dosyaları proje köküne aynı yollarla kopyala (üzerine yaz), `deploy.ps1` çalıştır, istemciyi yeniden export et.
Yeni tablo (`gate_first_clear`) açılışta kendiliğinden oluşur, mevcut veriye dokunulmaz.

## Değişen dosyalar
| Dosya | Değişiklik |
|---|---|
| `server/server_db.py` | `gate_first_clear` tablosu; `gate_finish` ilk bitireni belirler (`first`, `rings`); `rank_rows` (tüm hesapların puan girdileri); `load_player_state` -> `gate_rings` |
| `net_server.gd` | Rütbeler artık TÜM hesaplara göre (çevrimdışılar dahil), saatte bir; `rank_top` olayı; halka verme (`_gate_ring_awarded`); girişte anında rütbe |
| `rank_system.gd` | Şirket 1.si her zaman General (`GENERAL_MIN_POP = 1`); `build_board()`; `BOARD_SECONDS = 3600` |
| `rank_rings.gd` (YENİ) | Rozetin üstündeki halkaları çizer (1-2: gümüş-mavi, 3: ALTIN) |
| `net_game.gd` | Halka çözümleme, `rank_top` / `gg_ring` olayları |
| `main.gd` | Plakada halka çizimi, sıralama isteği ve olayları |
| `control_panel.gd` | İstatistik/profil sunucu sıralamasını kullanır; ilk 10 sunucudan, güncelleme saatleri gösterilir |
| `server/test_gate_rings.py` (YENİ) | DB testi: `python3 test_gate_rings.py` -> `SONUC: HEPSI GECTI` |

## Kurallar
- Her kapıyı (Alfa/Beta/Gamma) SUNUCUDA İLK bitiren oyuncu 1 halka alır. Halka kalıcıdır.
- En fazla 3 halka. 3 halka = rütbenin üstünde ALTIN halkalar.
- Adminler halka almaz. Kapıyı bitiren "kapı sahibi"dir (grup üyelerine halka verilmez).
- Her şirketin puan sırasındaki 1. oyuncusu General olur.
- Sıralama ve "En iyi 10" saatte bir güncellenir. Yeni bir hesap listede yoksa rütbeler en fazla dakikada bir yenilenir (ilk 10 listesi yine saatlik).

## Ayarlar (server/server_db.py başı, gate_finish üstü)
`GATE_RING_PER_COMPANY = False` -> tüm sunucuda ilk bitiren. `True` yaparsan her şirketin ilk bitireni halka alır.

## Notlar
- Godot bu ortamda yoktu; GDScript derlenip çalıştırılmadı (girinti ve sözdizimi elle gözden geçirildi). Python/DB tarafı çalıştırılarak test edildi. Hata verirse çıktıyı gönder.
- Eski sürüm istemciler halkalı oyuncuların rozetini göremez (rütbe alanı artık rütbe + 100 x halka). Oyuncular güncellemeli.
- Mevcut oyuncuların daha önce bitirdiği kapılar kayıtlı olmadığı için "ilk" belirlenemez; ilk bitirme bundan sonra sayılır.
