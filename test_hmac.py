import os
import hmac
import hashlib
import time
import secrets

# Read HMAC key exactly like both services do
key_file = "/opt/novagate/server/.hmac_key"
with open(key_file, "rb") as f:
    TOKEN_HMAC_KEY = f.read().strip()
print("HMAC key length:", len(TOKEN_HMAC_KEY))
print("HMAC key hex:", TOKEN_HMAC_KEY.hex())

# Generate a test token the same way auth_service does
account_id = 10
jti = secrets.token_urlsafe(32)
now = int(time.time())
expires_at = now + 1800
aud = "novagate-game-server"
payload = f"{account_id}:{jti}:{expires_at}:{aud}"
sig = hmac.new(TOKEN_HMAC_KEY, payload.encode("utf-8"), hashlib.sha256).hexdigest()
token = f"{account_id}:{jti}:{expires_at}:{aud}:{sig}"
print("Generated token:", token)

# Now verify it the same way server_db does
parts = token.split(":")
print("Parts count:", len(parts))
if len(parts) == 5:
    aid_str, jti2, exp_str, aud2, sig2 = parts
    print("aud match:", aud2 == "novagate-game-server")
    print("expired:", int(time.time()) > int(exp_str))
    
    # Recompute HMAC
    payload2 = f"{aid_str}:{jti2}:{exp_str}:{aud2}"
    expected_sig = hmac.new(TOKEN_HMAC_KEY, payload2.encode("utf-8"), hashlib.sha256).hexdigest()
    print("Expected sig:", expected_sig)
    print("Actual sig  :", sig2)
    print("HMAC match:", hmac.compare_digest(expected_sig, sig2))
