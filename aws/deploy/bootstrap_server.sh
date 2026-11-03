#!/bin/bash
# ============================================================
#  NOVAGATE AWS EC2 bootstrap (Ubuntu 24.04, t3.medium)
#  Instance ilk acildiginda (user-data) veya SSM Run Command ile cagrilir.
#  - Godot 4.7.2 linux x86_64 kurulumu
#  - Proje dosyalarini S3'ten cekip /opt/novagate'ye acma
#  - Godot kaynak importu (ilk acilis, headless)
#  - systemd servisi kurulumu + otomatik baslatma
#  Not: deploy bucket adini parametreyle ver: bootstrap_server.sh <bucket> <region>.
# ============================================================
set -euo pipefail

BUCKET="${1:-novagate-darkorbit-deploy}"
REGION="${2:-eu-central-1}"
GODOT_VER="4.7.2-stable"
GODOT_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VER}/Godot_v${GODOT_VER}_linux.x86_64.zip"

log() { echo "[NOVAGATE-BOOT] $(date -u +%H:%M:%S) $*"; }

log "paketsel kurulumlar basliyor"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq unzip ca-certificates curl fontconfig >/dev/null
# headless godot icin tipik bagimliliklar (x86_64 linux editor binary)
apt-get install -y -qq libfontconfig1 libxkbcommon0 libxi6 libxinerama1 libxcursor1 libxext6 libxrandr2 >/dev/null
if ! command -v aws >/dev/null 2>&1; then
  apt-get install -y -qq awscli >/dev/null
fi

# --- swap (t3.micro 1GB RAM icin guvenlik agi) ---
if [ ! -f /swapfile ]; then
  log "2GB swapfile olusturuluyor"
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  echo "/swapfile none swap sw 0 0" >> /etc/fstab
  echo "vm.swappiness=15" > /etc/sysctl.d/90-novagate-swap.conf
  sysctl -p /etc/sysctl.d/90-novagate-swap.conf >/dev/null
fi

log "godot $GODOT_VER indiriliyor"
if [ ! -x /opt/godot/godot ]; then
  mkdir -p /opt/godot
  curl -fsSL -o /tmp/godot.zip "$GODOT_URL"
  unzip -oq /tmp/godot.zip -d /tmp/godot
  mv /tmp/godot/Godot_v*_*linux.x86_64 /opt/godot/godot
  chmod +x /opt/godot/godot
fi
/opt/godot/godot --version | head -1

log "proje paketi S3'ten cekiliyor (bucket=$BUCKET)"
useradd -r -m -s /usr/sbin/nologin novagate 2>/dev/null || true
mkdir -p /home/novagate && chown -R novagate:novagate /home/novagate || true
rm -rf /opt/novagate
mkdir -p /opt/novagate
aws s3 cp "s3://${BUCKET}/deploy/novagate-latest.zip" /tmp/novagate.zip --region "$REGION"
unzip -oq /tmp/novagate.zip -d /opt/novagate
chown -R novagate:novagate /opt/novagate

log "godot kaynak importu (headless)"
sudo -u novagate /opt/godot/godot --headless --path /opt/novagate --import || log "import uyari bitti"

log "systemd servisi kuruluyor"
cat >/etc/systemd/system/novagate-server.service <<'EOF'
[Unit]
Description=NOVAGATE oyun sunucusu (Godot 4 headless, ENet UDP 7777)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=novagate
Group=novagate
WorkingDirectory=/opt/novagate
ExecStart=/opt/godot/godot --headless --path /opt/novagate -- --server --port=7777
Restart=on-failure
RestartSec=5
StartLimitBurst=0
KillSignal=SIGINT
TimeoutStopSec=15
LimitNOFILE=65536
Environment=LANG=C.UTF-8
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable novagate-server.service
systemctl restart novagate-server.service
sleep 8
systemctl is-active novagate-server.service || { journalctl -u novagate-server.service -n 50 --no-pager; exit 1; }
journalctl -u novagate-server.service -n 20 --no-pager

# --- log rotasyonu (journald siniri) ---
mkdir -p /etc/systemd/journald.conf.d
cat >/etc/systemd/journald.conf.d/30-novagate.conf <<'EOF'
[Journal]
SystemMaxUse=300M
MaxRetentionSec=30day
EOF
systemctl restart systemd-journald

# --- gunde bir kez config yedegi S3'e ---
cat >/etc/systemd/system/novagate-backup.timer <<'EOF'
[Unit]
Description=NOVAGATE gunluk config yedegi (S3)

[Timer]
OnCalendar=*-*-* 04:17:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
cat >/etc/systemd/system/novagate-backup.service <<EOF
[Unit]
Description=NOVAGATE gunluk config yedegi
[Service]
Type=oneshot
User=novagate
ExecStart=/bin/bash -c 'ts=\$(date -u +%Y-%m-%d); tar czf /tmp/novagate_cfg_\$ts.tgz -C /opt novagate; aws s3 cp /tmp/novagate_cfg_\$ts.tgz "s3://\$BUCKET/backup/novagate_cfg_\$ts.tgz" --region \$REGION; rm -f /tmp/novagate_cfg_\$ts.tgz'
Environment=BUCKET=$BUCKET
Environment=REGION=$REGION
EOF
systemctl daemon-reload
systemctl enable --now novagate-backup.timer

journalctl -u novagate-server.service -n 20 --no-pager
log "BOOTSTRAP-TAMAM"
