from argon2 import PasswordHasher
ph = PasswordHasher()
with open('/tmp/admin_password.txt') as f:
    pw = f.read().strip()
print(ph.hash(pw))
