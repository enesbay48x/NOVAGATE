def verify_and_consume_token(token: str, instance_id: str) -> dict | None:
    """
    Jetonu dogrular ve atomik olarak kullanildi olarak isaretler.
    Ayni jeton ikinci kez kullanilamaz.
    Dondurur: {"account_id": int} veya None
    """
    try:
        parts = token.split(":")
        if len(parts) != 5:
            log.warning("verify: RED - parca sayisi=%d (beklenen 5)", len(parts))
            return None
        account_id_str, jti, expires_at_str, aud, sig = parts

        if aud != "novagate-game-server":
            log.warning("verify: RED - aud uyusmazligi (account_id=%s)", account_id_str)
            return None

        expires_at = int(expires_at_str)
        if int(time.time()) > expires_at:
            log.warning("verify: RED - sure dolmus (account_id=%s)", account_id_str)
            return None

        # HMAC dogrulama
        TOKEN_HMAC_KEY = None
        env_key = os.environ.get("NOVAGATE_TOKEN_HMAC_KEY")
        if env_key:
            TOKEN_HMAC_KEY = env_key.encode("utf-8")
        else:
            key_file = os.environ.get("NOVAGATE_TOKEN_KEY_FILE")
            if key_file:
                try:
                    with open(key_file, "rb") as f:
                        TOKEN_HMAC_KEY = f.read().strip()
                except FileNotFoundError:
                    log.warning("verify: RED - HMAC anahtar dosyasi bulunamadi")
                    return None
        if TOKEN_HMAC_KEY is None:
            log.warning("verify: RED - HMAC anahtari yok")
            return None

        payload = f"{account_id_str}:{jti}:{expires_at_str}:{aud}"
        expected_sig = hmac.new(TOKEN_HMAC_KEY, payload.encode("utf-8"), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(expected_sig, sig):
            log.warning("verify: RED - HMAC uyusmazligi (account_id=%s)", account_id_str)
            return None

        account_id = int(account_id_str)

        # ATOMIK: used_tokens kaydi
        conn = get_db()
        try:
            conn.execute("BEGIN IMMEDIATE")
            existing = conn.execute(
                "SELECT jti FROM used_tokens WHERE jti = ?", (jti,)
            ).fetchone()
            if existing:
                conn.execute("ROLLBACK")
                log.warning("verify: RED - token daha once kullanildi (jti=%s)", jti[:16])
                return None

            conn.execute(
                "INSERT INTO used_tokens (jti, account_id, used_at, expires_at, instance_id) "
                "VALUES (?, ?, ?, ?, ?)",
                (jti, account_id, int(time.time()), expires_at, instance_id),
            )
            conn.execute("COMMIT")
            return {"account_id": account_id}
        except sqlite3.OperationalError as e:
            try:
                conn.execute("ROLLBACK")
            except Exception:
                pass
            log.warning("verify: RED - veritabani hatasi: %s", str(e))
            return None
        finally:
            conn.close()
    except Exception:
        log.exception("verify: RED - beklenmeyen hata")
        return None

