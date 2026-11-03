# Rapor: Giriş ekranında "TLS bağlantı hatası: 2"

**Tarih:** 3 Kasım 2026  
**Durum:** Sadece inceleme yapıldı. Hiçbir kod/yapılandırma/sertifika **değiştirilmedi**.

---

## 1. Hata mesajının kaynağı

`net.gd` (istemci ağ katmanı, autoload "Net"):

- `login_via_tls()` (net.gd:80-89) şu adrese istek atar:
  `https://18.117.15.199:8444/login`  (`AUTH_HOST = "18.117.15.199"`, `AUTH_HTTPS_PORT = 8444`; net.gd:32-33, 86)
- Yanıt işleme (net.gd:92-101):
  ```gd
  if result != HTTPRequest.RESULT_SUCCESS:
      last_error = "TLS baglanti hatasi: %d" % result
  ```
- Gözlemlenen `result = 2` → Godot 4'de `HTTPRequest.RESULT_CANNOT_CONNECT` ("bağlantı kurulamadı").
- Bu kod, **TCP bağlantısı kurulamaması VEYA TLS el sıkışmasının (sertifika doğrulama dahil) başarısız olmasının ardından HTTP yanıtı alınamadığı** durumlarda üretilir. `net.gd:98` tek bir mesajla yansıtılıyor, dolayısıyla "hata 2" sadece bağlantı/el sıkışma seviyesinde başarısız olduğunu söyler, ayrıntı vermez.

---

## 2. İstemci sertifika yükleme kodu (net.gd)

```gd
var _cert := X509Certificate.new()
if _cert.load("res://auth_cert_public.crt") == OK:
    tls_opts = TLSOptions.client(_cert, "novagate.local")
    auth_http_request.set_tls_options(tls_opts)
else:
    push_error("[NET] auth_cert_public.crt yuklenemedi ...")
```

- Dosya: `res://auth_cert_public.crt` (workspace kökünde mevcut, okunuyor).
- Sabitlenen (pinned) eş adı: `novagate.local` (`TLSOptions.client` ikinci parametresi).
- Yükleme başarısız olsa bile son kullanıcıya giden mesaj aynı "TLS bağlantı hatası: 2" kalır.

---

## 3. `auth_cert_public.crt` sertifika ayrıntıları (ayrıştırıldı)

| Özellik | Değer |
|---------|-------|
| Subject CN | `novagate.local` |
| Issuer CN | `novagate.local` (kendi tarafı imzalı / self-signed) |
| Not Before | `2026-11-02 21:14:02 UTC` = **2026-11-03 00:14:02 Türkiye saati (UTC+3)** |
| Not After | `2029-02-04 21:14:02 UTC` → **süresi DOLMADI** |
| SAN | `DNS: novagate.local` **ve** `IP: 18.117.15.199` |
| Anahtar | RSA public key (PEM) |

**Yorum:**
- **Süresi dolmuşluk hata DEĞİL:** sertifika 2029-02-04'e kadar geçerli.
- **CN/SAN uyuşmazlığı DEĞİL:** istemcinin beklediği `novagate.local` DNS SAN'da var, ve bağlandığı IP `18.117.15.199` de IP SAN'da var.
- **Critik bulgu:** `NotBefore` = 3 Kasım 2026 00:14:02 Türkiye saati. Bugün tarih **tam olarak 3 Kasım 2026**. Eğer istemci veya sunucunun yerel saati bu dakikadan önceyse, TLS el sıkışması *"sertifika henüz geçerli değil"* (certificate not yet valid) sebebiyle reddedilir ve sonuç olarak HTTPRequest `result = 2` döner. Bu, bugün oluşmuş bir hatayla tutarlıdır.
- Sistem saati (istemci + sunucu) ayrıca kontrol edilmeli; saat geriye alınmışsa aynı etki olur.

---

## 4. Sunucu tarafı TLS kurulumu

`server/auth_service.py`:

- `CERT_FILE = server/auth_cert.pem`, `KEY_FILE = server/auth_key.pem` (satır 81-82) — dosyalar mevcut.
- `build_ssl_context()` (satır 299-306): `load_cert_chain(certfile=CERT_FILE, keyfile=KEY_FILE)`, `verify_mode = ssl.CERT_NONE`, `minimum_version = TLSv1_2`.
- HTTPS login endpointi **`0.0.0.0:8444`** (satır 475-478) → production'da `https://18.117.15.199:8444/login` buna karşılık gelmesi beklenir.
- `server/auth_cert.pem` Subject'i de `CN=novagate.local` ve bitiş tarihi aynı (`2029-02-04`) → istemci ile sunucu aynı sertifika çiftini kullanıyor.

`nginx_novagate.conf` (production AWS yapılandırması):

- `listen 8447 ssl`, `server_name 18.117.15.199`, `ssl_certificate /etc/nginx/server.crt` (bu makinede yok, CN'si bilinmiyor), proxy `127.0.0.1:8445` (admin panel, `admin_panel.py:25`).
- Nginx **8447**'de dinler; istemci **8444**'e bağlanıyor. Üretimde 8444'te neyin dinlediği (auth_service mi, başka bir süreç mi) bu dosya setiyle doğrulanamadı.

---

## 5. Muhtemel nedenler (sıralı, hiçbir şey değiştirilmedi)

1. **(En yüksek olasılık) Sertifika henüz geçerli değil.** `notBefore` Türkiye saatiyle 3 Kasım 2026 00:14:02; bugün 3 Kasım 2026. Yerel saat bu değerden önceyse TLS el sıkışması başarısız olur → HTTPRequest `RESULT_CANNOT_CONNECT (2)`.
2. **18.117.15.199:8444'te hizmet açık değil.** TCP bağlantısı kurulamazsa doğrudan `RESULT_CANNOT_CONNECT (2)` döner. `aws_test.py` bu portu test eder ama bu ortamdan ağa erişilemediği için doğrulanamadı.
3. Üretimde 8444'te auth_service yerine farklı bir TLS süreci dinliyorsa ve sunucu sertifikası ile istemci pinlemesi (`novagate.local`) arasında uyuşmazlık varsa el sıkışma bozulur. Bu dosya setiyle doğrulanamadı (`/etc/nginx/server.crt` erişilebilir değil).

---

## 6. Engellenenler değildir

- Sertifika süresi dolması → **Hayır** (2029-02-04).
- CN/SAN uyuşmazlığı → **Hayır** (DNS: novagate.local + IP: 18.117.15.199 var).
- İstemci sertifika dosyasının yok olması / yüklenememesi → kodda başarılı-yol var; dosya mevcut ve okunuyor (yoksa da aynı genel mesaj çıkıyor, ayrıştırmaya izin vermez).

---

## 7. Eksik bilgiler / doğrulanması gerekenler

- İstemci makinesinin ve sunucunun **kesin yerel saati** (`notBefore = 3 Kasım 2026 00:14:02` ile karşılaştırmak için).
- `18.117.15.199:8444`'ün şu anda açık olup olmadığı (`aws_test.py` ile deneyilebilir).
- Üretim sunucusundaki asıl TLS sertifikası (`/etc/nginx/server.crt` veya production auth_service sertifikası) ve CN/SAN'ı.

---

## 8. Öneri (hiçbir şey henüz değiştirilmedi)

1. İstemci ve sunucu saatini kontrol et; `notBefore` (3 Kasım 2026 00:14:02 TR saati) geçtikten sonra tekrar dene.
2. `18.117.15.199:8444` portunun açık olduğunu ve auth_service'nin `server/auth_cert.pem` ile çalıştığını doğrula.
3. Gerekirse sertifikayı `notBefore`'yi geçmiş bir tarihe yeniden imzala (veya yeni sertifika üretip istemci `auth_cert_public.crt` ve sunucu `auth_cert.pem`/`auth_key.pem` çiftini güncelle).
4. Değişiklik yapmadan önce madde 7'deki eksik bilgilerin tamamlanması önerilir.
