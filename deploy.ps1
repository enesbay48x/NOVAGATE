# =============================================================================
# NOVAGATE DEPLOY SCRIPT (v2)
# Yerel proje -> AWS EC2 (Godot sunucusu + Python servisleri).
#
# ESKI SURUMDEKI HATALAR (bu yuzden sunucu hic guncellenmemis olabilir):
#   1) $FILES dizisinin sonunda fazladan virgul vardi -> PowerShell "Missing expression after ','" ile
#      betigi hic baslatmiyordu.
#   2) SSH/SCP komutlari tek bir metin olarak "& $full" ile calistiriliyordu -> PowerShell tum metni
#      programin ADI sanir, ssh hic calismaz.
#   3) Sadece 6 dosya yukleniyordu. net.gd (RPC tanimlari), safe_zone.gd, skill_tree.gd, auction.gd,
#      project.godot gibi dosyalar eski kaldigi icin istemci ile sunucu ayni RPC listesine sahip degildi.
#      Godot RPC'leri isimle degil SIRALI numarayla eslestirir; liste farkliysa NPC/kutu/kapi/odul
#      mesajlari sessizce kaybolur veya yanlis fonksiyona gider.
#   4) "Basarili" karari yalnizca Python token testine bakiyordu; Godot sunucusu acilmamis olsa bile
#      DEPLOY BASARILI yaziyordu.
# =============================================================================

$ErrorActionPreference = "Continue"   # yerel programlarin stderr'i betigi durdurmasin; cikis kodlarina bakilir

# --- Ayarlar ---
$SSH_KEY  = "C:\Users\Pc\.ssh\novagate_vds_ed25519"
$SSH_USER = "ubuntu"
$SSH_HOST = "18.117.15.199"
$TARGET   = "${SSH_USER}@${SSH_HOST}"
# BatchMode: sifre/passphrase sorusunda sessizce beklemez, hata verir. ServerAlive*: baglanti takilirsa ~30 sn'de kopar (sonsuz beklemez).
$SSH_OPTS = @("-i", $SSH_KEY, "-o", "ConnectTimeout=10", "-o", "StrictHostKeyChecking=accept-new", "-o", "BatchMode=yes", "-o", "ServerAliveInterval=10", "-o", "ServerAliveCountMax=3")

$PROJECT_DIR = "/opt/novagate"
$STAGE_DIR   = "/tmp/novagate_upload"
$BACKUP_TS   = Get-Date -Format "yyyyMMdd_HHmmss"
$BACKUP_DIR  = "/tmp/novagate_backup_$BACKUP_TS"
$TEST_SCRIPT = "test_register_and_login.py"

function SSH-Exec([string]$cmd, [switch]$AllowFail) {
    $out = & ssh @SSH_OPTS $TARGET $cmd 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0 -and -not $AllowFail) {
        throw "SSH komutu basarisiz (kod $code): $cmd`n$($out -join "`n")"
    }
    return ($out -join "`n")
}

function SCP-Upload([string]$local, [string]$remote) {
    $out = & scp @SSH_OPTS $local "${TARGET}:$remote" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "SCP yukleme basarisiz: $local -> $remote`n$($out -join "`n")" }
}

# --- Yuklenecek dosyalar (proje kokune gore GORECE yollar) ---
# Kokteki tum .gd dosyalari (sunucu ayni projeyi calistirir: main.gd bile parse edilir) + project.godot
# + iki Python servis dosyasi. Test/arac/yedek dosyalari haric.
$EXCLUDE = @("net_server_from_server.gd", "_probe_mp.gd", "_load_client.gd")
$files = @()
foreach ($g in Get-ChildItem -Path . -Filter "*.gd" -File) {
    if ($EXCLUDE -contains $g.Name) { continue }
    if ($g.Name -like "test_*") { continue }
    $files += $g.Name
}
$files += "project.godot"
$files += "server/auth_service.py"
$files += "server/server_db.py"

foreach ($f in $files) {
    if (-not (Test-Path $f)) { Write-Host "EKSIK DOSYA: $f" -ForegroundColor Red; exit 1 }
}
if (-not ($files -contains "net.gd")) { Write-Host "net.gd listede yok, durduruldu." -ForegroundColor Red; exit 1 }

Write-Host "=== NOVAGATE DEPLOY BASLADI: $BACKUP_TS  ($($files.Count) dosya) ===" -ForegroundColor Cyan

try {
    # --- 1. Yerel Python denetimi ---
    Write-Host "[1/6] Yerel Python dosyalari denetleniyor..." -ForegroundColor Yellow
    foreach ($f in ($files | Where-Object { $_ -like "*.py" })) {
        & python -m py_compile $f 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "PY_COMPILE HATA: $f" }
        Write-Host "  OK: $f"
    }

    # --- 2. Sunucudaki dosyalari yedekle ---
    Write-Host "[2/6] Sunucudaki mevcut dosyalar yedekleniyor: $BACKUP_DIR" -ForegroundColor Yellow
    $list = ($files | ForEach-Object { "'$_'" }) -join " "
    SSH-Exec ("sudo mkdir -p '$BACKUP_DIR' && cd '$PROJECT_DIR' && for f in $list; do if [ -f " + '"$f"' + " ]; then sudo cp --parents " + '"$f"' + " '$BACKUP_DIR'/; fi; done; true") | Out-Null

    # --- 3. Yukle (TEK paket: 27 ayri scp baglantisi yerine tek tar dosyasi; once /tmp'ye, sonra sudo ile yerine) ---
    Write-Host "[3/6] Dosyalar yukleniyor (tek paket)..." -ForegroundColor Yellow
    $archive = Join-Path $env:TEMP "novagate_upload_$BACKUP_TS.tar"
    & tar -cf $archive @files
    if ($LASTEXITCODE -ne 0) { throw "tar paketi olusturulamadi (Windows 10+ icindeki tar.exe gerekli)." }
    $sizeKb = [math]::Round((Get-Item $archive).Length / 1KB)
    Write-Host "  Paket hazir: $sizeKb KB. Sunucuya gonderiliyor..."
    SSH-Exec "rm -rf '$STAGE_DIR' && mkdir -p '$STAGE_DIR'" | Out-Null
    SCP-Upload $archive "/tmp/novagate_upload.tar"
    Remove-Item $archive -Force -ErrorAction SilentlyContinue
    Write-Host "  Gonderildi, sunucuda aciliyor..."
    SSH-Exec "tar -xf /tmp/novagate_upload.tar -C '$STAGE_DIR' && rm -f /tmp/novagate_upload.tar" | Out-Null
    SSH-Exec "sudo cp -r '$STAGE_DIR'/. '$PROJECT_DIR'/ && sudo chown -R novagate:novagate '$PROJECT_DIR' && rm -rf '$STAGE_DIR'" | Out-Null
    Write-Host "  Yuklendi."

    # --- 3b. Godot sinif onbellegini (class_name kayitlari) yenile ---
    Write-Host "[3b] Godot sinif onbellegi yenileniyor..." -ForegroundColor Yellow
    SSH-Exec "cd '$PROJECT_DIR' && G=`$(command -v godot || command -v godot4 || ls /opt/godot/* 2>/dev/null | head -1); if test -x `$G; then sudo -u novagate timeout 120 `$G --headless --path '$PROJECT_DIR' --import >/dev/null 2>&1; fi; true" -AllowFail | Out-Null

    # --- 4. Sunucuda Python derleme denetimi ---
    Write-Host "[4/6] Sunucuda Python denetimi..." -ForegroundColor Yellow
    foreach ($f in ($files | Where-Object { $_ -like "*.py" })) {
        SSH-Exec "sudo -u novagate python3 -m py_compile '$PROJECT_DIR/$f'" | Out-Null
        Write-Host "  OK: $f"
    }

    # --- 5. Servisleri yeniden baslat ---
    Write-Host "[5/6] Servisler yeniden baslatiliyor..." -ForegroundColor Yellow
    SSH-Exec "sudo systemctl restart novagate-db" | Out-Null
    Start-Sleep -Seconds 3
    SSH-Exec "sudo systemctl restart novagate-auth" | Out-Null
    SSH-Exec "sudo systemctl restart novagate-server" | Out-Null
    $portOpen = $false
    for ($i = 0; $i -lt 20; $i++) {
        $result = SSH-Exec "sudo ss -ltn | grep ':8444'" -AllowFail
        if ($result -match ":8444") {
            $portOpen = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $portOpen) {
        throw "HTTPS login portu 8444 40 saniye icinde acilamadi."
    }

    $authSt = (SSH-Exec "sudo systemctl is-active novagate-auth" -AllowFail).Trim()
    $dbSt   = (SSH-Exec "sudo systemctl is-active novagate-db" -AllowFail).Trim()
    $srvSt  = (SSH-Exec "sudo systemctl is-active novagate-server" -AllowFail).Trim()
    Write-Host "  novagate-auth:   $authSt"
    Write-Host "  novagate-db:     $dbSt"
    Write-Host "  novagate-server: $srvSt"
    if ($dbSt -ne "active" -or $srvSt -ne "active") { throw "Servis calismiyor (db=$dbSt, server=$srvSt)" }

    # Godot sunucusunun gunlugunde script hatasi var mi? (eksik dosya / parse hatasi burada gorunur)
    $log = SSH-Exec "sudo journalctl -u novagate-server --since '3 minutes ago' --no-pager -n 200" -AllowFail
    if ($log -match "SCRIPT ERROR|Parse Error|Failed to load script|Could not parse|Could not resolve|Cannot open file") {
        Write-Host $log
        throw "Godot sunucu gunlugunda script hatasi var."
    }
    if ($log -notmatch "NOVAGATE SUNUCUSU calisiyor") {
        Write-Host "  UYARI: 'NOVAGATE SUNUCUSU calisiyor' satiri gunlukte gorunmedi. Elle bak: sudo journalctl -u novagate-server -n 100" -ForegroundColor DarkYellow
    }

    # --- 6. Token testi ---
    Write-Host "[6/6] Test calistiriliyor..." -ForegroundColor Yellow
    $testOk = $false
    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        SCP-Upload $TEST_SCRIPT "/tmp/$TEST_SCRIPT"
        $testResult = SSH-Exec "sudo -u novagate python3 /tmp/$TEST_SCRIPT 2>&1" -AllowFail
        Write-Host $testResult
        if (($testResult -match "SUCCESS: Token verified") -and ($testResult -match "SUCCESS: Clan verified")) {
            $testOk = $true
            break
        }
        if ($attempt -eq 0) {
            Start-Sleep -Seconds 5
        }
    }
    if (-not $testOk) { throw "Token testi basarisiz." }

    Write-Host "=== DEPLOY BASARILI ===" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "HATA: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "=== DEPLOY BASARISIZ - yedege donuluyor ===" -ForegroundColor Red
    SSH-Exec "if [ -d '$BACKUP_DIR' ]; then sudo cp -a '$BACKUP_DIR'/. '$PROJECT_DIR'/ && sudo chown -R novagate:novagate '$PROJECT_DIR'; fi" -AllowFail | Out-Null
    SSH-Exec "sudo systemctl restart novagate-auth" -AllowFail | Out-Null
    SSH-Exec "sudo systemctl restart novagate-db" -AllowFail | Out-Null
    SSH-Exec "sudo systemctl restart novagate-server" -AllowFail | Out-Null
    $rbPortOpen = $false
    for ($i = 0; $i -lt 20; $i++) {
        $rbResult = SSH-Exec "sudo ss -ltn | grep ':8444'" -AllowFail
        if ($rbResult -match ":8444") {
            $rbPortOpen = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $rbPortOpen) {
        Write-Host "UYARI: Rollback sonrasi 8444 portu acilamadi." -ForegroundColor Yellow
    }
    Write-Host "Yedekten geri yuklendi (yedek: $BACKUP_DIR)." -ForegroundColor Yellow
    exit 1
}
