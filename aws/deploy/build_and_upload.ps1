# ============================================================
#  NOVAGATE DEPLOY (yerel taraf)
#   1) Proje dosyalarini paketle (.git/.godot/android/zip'ler hariç)
#   2) S3 surgune yukle:  s3://<bucket>/deploy/novagate-latest.zip
#   3) EC2'de bootstrap'i SSM Run Command ile tetikle (opsiyonel)
#  Kullanim:  pwsh ./aws/deploy/build_and_upload.ps1 <bucket> [tickle-run]
# ============================================================
param(
    [Parameter(Mandatory = $true)][string] $Bucket,
    [Parameter(Mandatory = $false)][string] $Region = "eu-central-1",
    [Parameter(Mandatory = $false)][string] $InstanceId = ""
)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$stage = Join-Path $env:TEMP "novagate_deploy_stage"
$zip   = Join-Path $env:TEMP "novagate-latest.zip"

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null

$excludeDirs = @(".git", ".godot", "android", "android_build", "andr", "diffs", "aws")
$excludeTopPatterns = @("Yeni klas*")
$files = Get-ChildItem $root -Recurse -File |
    Where-Object {
        $rel = $_.FullName.Substring($root.Length + 1)
        $top = ($rel -split '\\', 2)[0]
        $top -notin $excludeDirs -and
        ($excludeTopPatterns | Where-Object { $top -like $_ } | Measure-Object).Count -eq 0 -and
        $_.Extension -notin @(".zip", ".bak", ".bak2", ".diff") -and
        $_.Name -notmatch "(yedek|\.bak)" -and
        $_.Name -notin @("opencode.json")
    }

foreach ($f in $files) {
    $rel = $f.FullName.Substring($root.Length + 1)
    $dst = Join-Path $stage $rel
    $dstDir = Split-Path $dst -Parent
    if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    Copy-Item $f.FullName $dst -Force
}
"paketlenen dosya: $($files.Count)"

# Windows ters egik cizgi sorunu: Compress-Archive zip girdilerinde
# yol ayirici olarak "\" saklayabiliyor; Linux'ta unzip bu girdileri
# adinda "\" bulunan dosyalar olarak acar. bsdtar (Windows ile gelen tar)
# ise zip yazarken her zaman "/" kullanir; bu yuzden arsivi tar ile uretiyoruz.
if (Test-Path $zip) { Remove-Item $zip -Force }
tar.exe -a -c -f $zip -C $stage .
"zip boyutu: {0:N0} KB" -f ((Get-Item $zip).Length / 1KB)

# aws CLI once kurulu konumda aranir, bulunamazsa PATH'e bakilir
$aws = @("$env:ProgramFiles\Amazon\AWSCLIV2\aws.exe", "aws") |
    Where-Object { $_ -eq "aws" -or (Test-Path $_) } | Select-Object -First 1
& $aws s3 cp $zip "s3://$Bucket/deploy/novagate-latest.zip" --region $Region --no-progress

if ($InstanceId -ne "") {
    # Guncelleme scripti EC2 icinde /opt/deploy/ altinda durur (bootstrap kopyalar).
    $cmdJson = [PSCustomObject]@{ commands = @("bash /opt/deploy/update_server.sh $Bucket $Region") } | ConvertTo-Json -Compress
    & $aws ssm send-command `
        --region $Region `
        --instance-ids $InstanceId `
        --document-name "AWS-RunShellScript" `
        --comment "NOVAGATE update deploy" `
        --parameters $cmdJson `
        --output text
}
"Bitti."
