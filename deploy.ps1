# =============================================================================
# NOVAGATE DEPLOY SCRIPT
# Yerel proje klasöründeki güncel dosyaları AWS EC2 sunucusuna yükler,
# derleme denetimi yapar, servisleri yeniden başlatır ve test çalıştırır.
# =============================================================================

$ErrorActionPreference = "Stop"

# --- Ayarlar ---
$SSH_KEY   = "C:\Users\Pc\.ssh\novagate_vds_ed25519"
$SSH_USER  = "ubuntu"
$SSH_HOST  = "18.117.15.199"
$SSH       = "ssh -i `"$SSH_KEY`" -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new `"$SSH_USER`@`$SSH_HOST`"
$SCP       = "scp -i `"$SSH_KEY`" -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new"

$SERVER_DIR = "/opt/novagate/server"
$PROJECT_DIR = "/opt/novagate"

$BACKUP_TS = Get-Date -Format "yyyyMMdd_HHmmss"

# Yüklemek istediğimiz dosyalar (yerel -> sunucu)
$FILES = @(
    @{ Local = "server/auth_service.py"; Remote = "$SERVER_DIR/auth_service.py" },
    @{ Local = "server/server_db.py";    Remote = "$SERVER_DIR/server_db.py" },
    @{ Local = "net_server.gd";          Remote = "/opt/novagate/net_server.gd" },
    @{ Local = "main.gd";                Remote = "/opt/novagate/main.gd" },
)

# Test betiği
$TEST_SCRIPT = "test_register_and_login.py"

# =============================================================================
function SSH-Exec([string]$cmd) {
    $full = "$SSH `"$cmd`""
    & $full 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "SSH komut basarisiz: $cmd"
    }
}

function SCP-Upload([string]$local, [string]$remote) {
    $full = "$SCP `"$local`" `"$SSH_USER`@`$SSH_HOST`:$remote`""
    & $full 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "SCP yukleme basarisiz: $local -> $remote"
    }
}

# =============================================================================
Write-Host "=== NOVAGATE DEPLOY BASLADI: $BACKUP_TS ===" -ForegroundColor Cyan

# --- 1. Sunucudaki dosyaların zaman damgalı yedeği al ---
Write-Host "[1/7] Sunucudaki dosyalar yedekleniyor..." -ForegroundColor Yellow
$backupDir = "/tmp/novagate_backup_$BACKUP_TS"
SSH-Exec "mkdir -p `"$backupDir`""
foreach ($f in $FILES) {
    $remote = $f.Remote
    SSH-Exec "test -f `"$remote`" && sudo cp `"$remote`" `"$backupDir`/" || echo "HIÇ: $remote""
}
Write-Host "  Yedek dizin: $backupDir" -ForegroundColor Green

# --- 2. Yerel Python dosyalarını denetle ---
Write-Host "[2/7] Yerel Python dosyaları denetleniyor..." -ForegroundColor Yellow
$pyFiles = Get-ChildItem "server\*.py" -ErrorAction SilentlyContinue
foreach ($f in $pyFiles) {
    & python -m py_compile $f.FullName 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "PY_COMPILE HATA: $($f.FullName)"
    } else {
        Write-Host "  OK: $($f.Name)"
    }
}

# --- 3. Yerel .gd dosyalarını denetle (Godot varsa) ---
Write-Host "[3/7] Yerel .gd dosyaları denetleniyor..." -ForegroundColor Yellow
$gdFiles = Get-ChildItem "*.gd" -ErrorAction SilentlyContinue
foreach ($f in $gdFiles) {
    Write-Host "  SKIP (Godot yok yerelde): $($f.Name)" -ForegroundColor DarkGray
}
# Godot sunucuda varsa orada da denetlenecek (opsiyonel)

# --- 4. Dosyaları sunucuya yükle ---
Write-Host "[4/7] Dosyalar sunucuya yukleniyor..." -ForegroundColor Yellow
foreach ($f in $FILES) {
    Write-Host "  Yukleniyor: $($f.Local) -> $($f.Remote)"
    SCP-Upload $f.Local $f.Remote
    # Sahiplik ayarla
    SSH-Exec "sudo chown novagate:novagate `"$($f.Remote)`""
}

# --- 5. Sunucuda Python derleme denetimi ---
Write-Host "[5/7] Sunucuda Python derleme denetimi..." -ForegroundColor Yellow
foreach ($f in $FILES) {
    if ($f.Local -like "*.py") {
        SSH-Exec "sudo -u novagate python3 -m py_compile `"$($f.Remote)`""
        if ($LASTEXITCODE -ne 0) {
            Write-Error "REMOTE PY_COMPILE HATA: $($f.Remote)"
        } else {
            Write-Host "  OK: $($f.Remote)"
        }
    }
}

# --- 6. Servisleri yeniden baslat ---
Write-Host "[6/7] Servisler yeniden baslatiliyor..." -ForegroundColor Yellow
SSH-Exec "sudo systemctl restart novagate-db"
Start-Sleep -Seconds 3
SSH-Exec "sudo systemctl restart novagate-server"
Start-Sleep -Seconds 5

# Servis durumunu kontrol et
$authStatus = SSH-Exec "sudo systemctl is-active novagate-auth 2>&1"
$dbStatus   = SSH-Exec "sudo systemctl is-active novagate-db 2>&1"
$srvStatus  = SSH-Exec "sudo systemctl is-active novagate-server 2>&1"
Write-Host "  novagate-auth:  $authStatus" -ForegroundColor Gray
Write-Host "  novagate-db:    $dbStatus" -ForegroundColor Gray
Write-Host "  novagate-server:$srvStatus" -ForegroundColor Gray

# --- 7. Test calistir ---
Write-Host "[7/7] Test calistiriliyor..." -ForegroundColor Yellow
SCP-Upload $TEST_SCRIPT "/tmp/$TEST_SCRIPT"
$testResult = SSH-Exec "sudo -u novagate python3 /tmp/$TEST_SCRIPT 2>&1"
Write-Host $testResult

if ($testResult -match "SUCCESS: Token verified") {
    Write-Host "=== DEPLOY BASARILI ===" -ForegroundColor Green
    exit 0
} else {
    Write-Host "=== DEPLOY BASARISIZ - Yedeke donuluyor ===" -ForegroundColor Red
    foreach ($f in $FILES) {
        SSH-Exec "sudo cp `"$backupDir/$(Split-Path $f.Remote -Leaf)`" `"$($f.Remote)`""
        SSH-Exec "sudo chown novagate:novagate `"$($f.Remote)`""
    }
    SSH-Exec "sudo systemctl restart novagate-db"
    SSH-Exec "sudo systemctl restart novagate-server"
    Write-Host "Yedekten geri yuklendi." -ForegroundColor Yellow
    exit 1
}
