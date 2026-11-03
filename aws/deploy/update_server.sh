#!/bin/bash
# NOVAGATE sunucu guncelleme (EC2 icinde, SSM ile cagrilir)
# Kullanim: update_server.sh <bucket> <region>
set -e
BUCKET="${1}"
REGION="${2}"
[ -z "$BUCKET" ] && { echo "bucket eksi"; exit 1; }
REGION="${REGION:-eu-central-1}"

aws s3 cp "s3://${BUCKET}/deploy/novagate-latest.zip" /tmp/novagate.zip --region "$REGION"
rm -rf /opt/novagate_new
mkdir -p /opt/novagate_new
unzip -oq /tmp/novagate.zip -d /opt/novagate_new
chown -R novagate:novagate /opt/novagate_new
systemctl stop novagate-server || true
rm -rf /opt/novagate
mv /opt/novagate_new /opt/novagate
sudo -u novagate /opt/godot/godot --headless --path /opt/novagate --import || true
systemctl restart novagate-server
sleep 5
systemctl is-active novagate-server
