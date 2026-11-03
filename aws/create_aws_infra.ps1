# ============================================================
#  NOVAGATE - AWS infra kurulumu (tek seferlik, idempotent)
#  Bölge: eu-central-1 (Frankfurt) — kaynaklar burada olusur.
#  Auth bölgesi facilitate: aws login kullanicida yapilir (bölge fark etmez).
#  Kaynaklar:
#   - S3 deploy/yedek bucket (public erisim KAPALI, versioning ACIK)
#   - IAM role: SSM + bu bucket'a salt-okunur deploy / yedek yazma
#   - Security Group: yalnizca UDP 7777 (SSH portu ACILMAZ; yonetim SSM)
#   - EC2 t3.medium, Ubuntu 24.04, 20GB gp3, user-data bootstrap
#   - Elastic IP (EC2'ye bagliyken ucretsiz)
# Kullanim:  pwsh -File .\aws\create_aws_infra.ps1 -AccountId 165795704222
# ============================================================
param(
    [Parameter(Mandatory = $true)][string] $AccountId,
    [Parameter(Mandatory = $false)][string] $Region = "us-east-2",
    [Parameter(Mandatory = $false)][string] $Bucket = "",
    [Parameter(Mandatory = $false)][string] $InstanceType = "t3.micro",
    [Parameter(Mandatory = $false)][switch] $Spot
)
$ErrorActionPreference = "Continue"  # aws CLI stderr akisina karsi PowerShell 5.1 tuzaï¿½ï¿½ï¿½ onlemi
$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
if ($Bucket -eq "") { $Bucket = "novagate-deploy-$AccountId" }
$SGName = "novagate-sg"
$TagName = "novagate"

function Say($m) { Write-Host "[INFRA] $m" }

#Region sabit eu-central-1'de ozellikle kaydetme (auth bölgesi ile karismasin)
$env:AWS_DEFAULT_REGION = $Region

# --- S3 bucket -------------------------------------------------
aws s3api head-bucket --bucket $Bucket --region $Region 2>$null
if ($LASTEXITCODE -ne 0) {
    Say "S3 bucket olusturuluyor: $Bucket"
    aws s3api create-bucket --bucket $Bucket --region $Region --create-bucket-configuration LocationConstraint=$Region | Out-Null
    aws s3api put-public-access-block --bucket $Bucket --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" | Out-Null
    aws s3api put-bucket-versioning --bucket $Bucket --versioning-configuration Status=Enabled | Out-Null
} else { Say "S3 bucket zaten var: $Bucket" }

# --- IAM role --------------------------------------------------
$roleName = "novagate-server-role"
$profileName = "novagate-server-profile"
aws iam get-role --role-name $roleName 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Say "IAM role olusturuluyor: $roleName"
    $trust = [PSCustomObject]@{
        Version = "2012-10-17"
        Statement = @(
            @{ Effect = "Allow"; Principal = @{ Service = "ec2.amazonaws.com" }; Action = "sts:AssumeRole" }
        )
    }
    $trustJson = $trust | ConvertTo-Json -Depth 6
    $tmpTrust = Join-Path $env:TEMP "novagate_trust.json"
    [System.IO.File]::WriteAllText($tmpTrust, $trustJson)
    aws iam create-role --role-name $roleName --assume-role-policy-document file://$tmpTrust | Out-Null
    aws iam attach-role-policy --role-name $roleName --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" | Out-Null
    # Least privilege: sadece bu bucket'a erisim
    $s3policy = [PSCustomObject]@{
        Version = "2012-10-17"
        Statement = @(
            @{ Effect = "Allow"; Action = @("s3:GetObject","s3:PutObject","s3:DeleteObject"); Resource = "arn:aws:s3:::$Bucket/*" },
            @{ Effect = "Allow"; Action = @("s3:ListBucket"); Resource = "arn:aws:s3:::$Bucket" }
        )
    } | ConvertTo-Json -Depth 6
    $tmpS3p = Join-Path $env:TEMP "novagate_s3policy.json"
    [System.IO.File]::WriteAllText($tmpS3p, $s3policy)
    aws iam put-role-policy --role-name $roleName --policy-name novagate-s3-scoped --policy-document file://$tmpS3p | Out-Null
} else { Say "IAM role zaten var: $roleName" }

$profRoles = (aws iam get-instance-profile --instance-profile-name $profileName --query "InstanceProfile.Roles[0].RoleName" --output text 2>$null)
$profExit = $LASTEXITCODE
if ($profExit -ne 0 -or [string]::IsNullOrWhiteSpace("$profRoles") -or "$profRoles" -eq "None") {
    if ($profExit -ne 0) {
        aws iam create-instance-profile --instance-profile-name $profileName 2>$null
        Start-Sleep -Seconds 5
    }
    aws iam add-role-to-instance-profile --instance-profile-name $profileName --role-name $roleName
    Start-Sleep -Seconds 10
} else { Say "Instance profile var (rol: $profRoles)" }

# --- Security Group -------------------------------------------
$vpcId = aws ec2 describe-vpcs --region $Region --filters Name=isDefault,Values=true --query "Vpcs[0].VpcId" --output text
$sg = (aws ec2 describe-security-groups --region $Region --filters Name=group-name,Values=$SGName --query "SecurityGroups[0].GroupId" --output text)
if ($sg -eq "None" -or [string]::IsNullOrWhiteSpace($sg)) {
    Say "Security Group olusturuluyor: $SGName (yalnizca UDP 7777)"
    $sg = aws ec2 create-security-group --region $Region --group-name $SGName --description "NOVAGATE ENet UDP 7777" --vpc-id $vpcId --query "GroupId" --output text
    aws ec2 authorize-security-group-ingress --region $Region --group-id $sg --protocol udp --port 7777 --cidr 0.0.0.0/0 | Out-Null
    # SSH HIC ACILMAZ; yonetim SSM ile. Gerekirse siz --cidr 'a kendi IP'nizi ekleyin.
} else { Say "SG zaten var: $sg" }

# --- EC2 --------------------------------------------------------
$Ami = (aws ssm get-parameters --region $Region --names "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id" --query "Parameters[0].Value" --output text).Trim()
Say "Ubuntu 24.04 AMI: $Ami"

$existing = (aws ec2 describe-instances --region $Region --filters Name=tag:Name,Values=$TagName Name=instance-state-name,Values=running,stopped,pending,stopping --query "Reservations[].Instances[0].InstanceId" --output text)
if ($existing -and $existing -ne "None") {
    Say "EC2 instance zaten var: $existing"
} else {
    # on-demand (Free-Tier hesaplarinda yalnizca micro tip aileleri)
    Say "EC2 instance olusturuluyor ($InstanceType, on-demand)"
    # user-data: bootstrap scriptini S3'ten cek ve calistir
    $userData = @"
#!/bin/bash
set -euo pipefail
apt-get update -qq && apt-get install -y -qq unzip curl awscli >/dev/null
mkdir -p /opt/deploy
aws s3 cp "s3://$Bucket/deploy/update_server.sh" /opt/deploy/update_server.sh --region $Region || true
aws s3 cp "s3://$Bucket/deploy/bootstrap_server.sh" /tmp/bootstrap_server.sh --region $Region
bash /tmp/bootstrap_server.sh $Bucket $Region
"@
    $tmpUd = Join-Path $env:TEMP "novagate_user_data.sh"
    [System.IO.File]::WriteAllText($tmpUd, $userData)

    $bdmJson = '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":20,"VolumeType":"gp3","DeleteOnTermination":true}}]'
    $tagsJson = '[{"ResourceType":"instance","Tags":[{"Key":"Name","Value":"novagate"},{"Key":"Project","Value":"darkorbit3d"}]}]'
    $tmpBdm = Join-Path $env:TEMP "novagate_bdm.json"
    $tmpTags = Join-Path $env:TEMP "novagate_tags.json"
    [System.IO.File]::WriteAllText($tmpBdm, $bdmJson)
    [System.IO.File]::WriteAllText($tmpTags, $tagsJson)

    $runParams = @(
        "ec2","run-instances","--region",$Region,
        "--image-id",$Ami,
        "--instance-type",$InstanceType,
        "--security-group-ids",$sg,
        "--iam-instance-profile","Name=$profileName",
        "--block-device-mappings","file://$tmpBdm",
        "--tag-specifications","file://$tmpTags"
    )
    if ($Spot) {
        Say "(SPOT bu hesap SCP ile engelli - on-demand devam)"
    }
    $runParams += @("--user-data","file://$tmpUd","--query","Instances[0].InstanceId","--output","text")
    $existing = (aws @runParams).Trim()
    if ([string]::IsNullOrWhiteSpace($existing)) {
        Say "HATA: RunInstances basarisiz (assagi detay)"
        exit 1
    }
    Say "EC2 instance olusturuldu: $existing"
}

# --- Elastic IP -------------------------------------------------
$eip = (aws ec2 describe-addresses --region $Region --filters Name=tag:Name,Values=$TagName --query "Addresses[0].PublicIp" --output text)
if (-not $eip -or $eip -eq "None") {
    Say "Elastic IP aliniyor"
    $eip = (aws ec2 allocate-address --region $Region --domain vpc --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=$TagName}]" --query "PublicIp" --output text).Trim()
    Say "EIP: $eip"
} else { Say "EIP zaten var: $eip" }

$allocId = (aws ec2 describe-addresses --region $Region --public-ips $eip --query "Addresses[0].AllocationId" --output text).Trim()
$mapped  = (aws ec2 describe-addresses --region $Region --public-ips $eip --query "Addresses[0].InstanceId" --output text).Trim()
if ($mapped -eq "None") {
    aws ec2 associate-address --region $Region --allocation-id $allocId --instance-id $existing | Out-Null
    Say "EIP instance'a baglandi"
}

Write-Host ""
Say "OZET: bucket=$Bucket, sg=$sg, instance=$existing, eip=$eip"
Say "Servis: UDP 7777 (ENet) - yonetim: SSM (SSH kapali)"
Write-Host ""
Say "SONRAKI ADIM: EC2 running'e gecip servisi dogrulamak icin:"
Say "  aws ssm send-command ... bash /opt/deploy/update_server.sh $Bucket $Region"
