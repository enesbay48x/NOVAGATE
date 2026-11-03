import sys
sys.path.insert(0, '/opt/novagate/admin')
import admin_panel as a

c = a.app.test_client()

# GET login page to get csrf token
r = c.get('/admin/login')
print('GET status:', r.status_code)

# Get token from HTML
html = r.data.decode()
import re
m = re.search(r'name="csrf_token" value="([^"]+)"', html)
if m:
    csrf_form = m.group(1)
    print('CSRF form token:', csrf_form[:30] + '...')
else:
    print('CSRF token NOT found in HTML!')
    sys.exit(1)

# POST login with csrf token (cookie is sent automatically by test client)
r2 = c.post('/admin/login', data={
    'username': 'NOVAGATE',
    'password': 'ExjALfPjPLJeP0QW7BM0CDbShE36c44eqL3KK6GbMdo',
    'csrf_token': csrf_form,
})
print('POST status:', r2.status_code)
print('POST location:', r2.location)
if r2.data:
    print('POST data:', r2.data[:200])
