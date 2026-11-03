# NOVAGATE AWS OPERASYON KILAVUZU (us-east-2)

## Mimari

```
Godot 4 istemcileri (PC / Android / iOS)
        |  ENet (UDP 7777) - NPC, PvP, sohbet, grup, jumpgate
        v
   Elastic IP (18.117.15.199)  ->  EC2 t3.micro  i-094c6723c2dbf082f
                   (Ubuntu 24.04, us-east-2, on-demand, Free-Tier)
                   /opt/godot/godot --headless --path /opt/novagate -- --server --port=7777
                   systemd: novagate-server.service (Restart=on-failure, 5 sn)
                   2GB swapfile; journald log rotasyonu (300M, 30 gun)
                   yonetim: SSM Run Command (SSH portu ACIK DEGIL)
       S3 bucket: novagate-deploy-257851647480
                  deploy/novagate-latest.zip + backup/tarih.zip (versioning)
```

- Veritabani YOK: mevcut sistemde hesaplar istemci-taraflidir (user://). Sunucuda
  kalici state yok; bu nedenle RDS kurulmadi (kodda olmayan sistem uydurulmadi).
- KONU BOLGE: bu Ctrl Shift Create hesabinin SCP'si sadece us-east-2'ye izin veriyor.
  eu-central-1 + SPOT kapali. Frankfurt gecikmesi onemsizse us-east-2 kullanilacak.
- Gelistirme: editorde `NOVAGATE_SERVER=127.0.0.1:7777` env ile local sunucuya baglan.
- Yayin istemcisi: release export otomatik (PROD_SERVER_ADDR, net.gd) 18.117.15.199:7777

## SUNUCU BILGILERI

| Kaynak | Deger |
|---|---|
| Public IP | 18.117.15.199 |
| Public DNS | ec2-18-117-15-199.us-east-2.compute.amazonaws.com |
| Instance | i-094c6723c2dbf082f (t3.micro, Ubuntu 24.04) |
| Port | UDP 7777 (ENet) |
| SSH | KAPALI (SSM ile) |
| S3 | s3://novagate-deploy-257851647480 |
| SG | sg-085f7789799667f29 |

## KULLANIM

Servis durumu + log (tek seferlik):
```
aws ssm send-command --region us-east-2 --instance-ids i-094c6723c2dbf082f \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["systemctl status novagate-server --no-pager; journalctl -u novagate-server -n 50 --no-pager"]' \
  --query "Command.CommandId" --output text
```
Komut cikti okuma: `aws ssm get-command-invocation --command-id <ID> --instance-id i-... --output text`

Kod guncelleme (yerel):
```
pwsh -File .\aws\deploy\build_and_upload.ps1 novagate-deploy-257851647480 -Region us-east-2 -InstanceId i-094c6723c2dbf082f
```

Yedekleme: gunluk 04:17 UTC config tar -> s3://.../backup/ + S3 versioning.
Deploy ZIP'miz de deploy/ altinda kalici olarak durably duruyor.

## MALIYET (tahmin, aylik)

- t3.micro FREE (aylik 750 saat ucretsiz kota)       : $0
- EBS 20GB gp3                                        : ~$1.60
- Elastic IP (instance'a bagliyken)                   : $0
- S3 (30GB versioned backup)                          : ~$0.7
- Oyuncu trafigi (egress)                             : ~$5-25
- TOPLAM (kredi ortami dahil)                         : ~$7-30/ay
- 77 USD kredi durumu: calismaya devam eder, misali回落 paydow.

## YAPILMAYAN / SONRAKI ADIMLAR (acik)

- 100 eszamanli yuk testi HENUZ YAPILMADI; kurulum sonrasi yapilacaktir.
- Istemci release export (Android/iOS) sonraki is: PROD_SERVER_ADDR otomatik baglar.
- Eger 100 oyuncu t3.micro'da basarili olmazsa tek yol: program SCP'sinde
  spot/eu-central-1 kilidinin acilmasi veya yeni bireysel bir hesap.
