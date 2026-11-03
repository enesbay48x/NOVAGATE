import urllib.request
import urllib.parse
import http.cookiejar

jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))

# GET login page
req = opener.open("http://127.0.0.1:8445/admin/login")
html = req.read().decode()
print("GET status:", req.status)

# Extract csrf token from HTML
import re
m = re.search(r'name="csrf_token" value="([^"]+)"', html)
if m:
    csrf_token = m.group(1)
    print("CSRF token from HTML:", csrf_token[:20] + "...")
else:
    print("CSRF token NOT found in HTML!")
    csrf_token = ""

# Find csrf cookie
csrf_cookie = ""
for c in jar:
    if c.name == "csrf_token":
        csrf_cookie = c.value
        print("CSRF cookie:", csrf_cookie[:20] + "...")
        break

if not csrf_cookie:
    print("CSRF cookie NOT found!")

# POST login
data = urllib.parse.urlencode({
    "username": "NOVAGATE",
    "password": "ExjALfPjPLJeP0QW7BM0CDbShE36c44eqL3KK6GbMdo",
    "csrf_token": csrf_token,
}).encode()
req2 = urllib.request.Request("http://127.0.0.1:8445/admin/login", data=data, method="POST")
try:
    resp = opener.open(req2)
    print("POST status:", resp.status)
    body = resp.read().decode()
    print("Redirect to:", resp.geturl())
except urllib.error.HTTPError as e:
    print("POST error status:", e.code)
    print(e.read().decode()[:200])
