import os, sys
sys.path.insert(0, 'server')
from server_db import verify_and_consume_token

# Check env
print("NOVAGATE_TOKEN_HMAC_KEY:", os.environ.get("NOVAGATE_TOKEN_HMAC_KEY"))

# Test with a known token
token = "4:pT4oWmtocc8Iugo23HnjRQmtOTPg:x:novagate-game-server:sig"
result = verify_and_consume_token(token, "test-instance-001")
print("Result:", result)
