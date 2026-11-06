#!/bin/bash
###############################################################################
# NOVAGATE AWS Sunucu Performans ve Kasma Teşhisi Diagnostic Scripti
# TAMAMI SALT OKUNUR - Hiçbir dosya değiştirilmez, kurulmaz, yeniden başlatılmaz.
# Çıktı: novagate_diagnostic_report_YYYYMMDD_HHMMSS.txt
###############################################################################

set -u

REPORT_DIR="$(pwd)"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="${REPORT_DIR}/novagate_diagnostic_report_${TIMESTAMP}.txt"

# ---- Yardımcı fonksiyonlar ----

section() {
    echo ""
    echo "================================================================================"
    echo "$1"
    echo "==============================================================================="
    echo ""
}

cmd_or_na() {
    # Parametre: komut
    if command -v "$1" >/dev/null 2>&1; then
        eval "$1" 2>&1 || echo "[HATA: Komut çalıştırılamadı: $1]"
    else
        echo "[KOMUT BULUNAMADI: $1]"
    fi
}

safe_cmd() {
    # Bir komutu çalıştırır, yoksa NA yazdırır
    local desc="$1"; shift
    echo "--- $desc ---"
    if command -v "$1" >/dev/null 2>&1; then
        "$@" 2>&1 || echo "[ÇALIŞTIRMA HATASI: $*]"
    else
        echo "[KOMUT BULUNAMADI: $1]"
    fi
    echo ""
}

# ==============================================================================
# RAPOR BAŞLANGICI
# ==============================================================================

{
echo "================================================================================"
echo "NOVAGATE AWS SUNUCU PERFORMANS VE KASMA TEŞHISI RAPORU"
echo "================================================================================"
echo "Tarih/Saat      : $(date)"
echo "Sunucu Hostname : $(hostname 2>/dev/null || echo 'BULUNAMADI')"
echo "Çalışma Dizini  : ${REPORT_DIR}"
echo "Rapor Dosyası   : ${REPORT_FILE}"
echo "Kullanıcı       : $(whoami 2>/dev/null || echo 'BULUNAMADI')"
echo "================================================================================"

# ==============================================================================
# 1. SİSTEM VE DONANIM BİLGİLERİ
# ==============================================================================
section "1. SİSTEM VE DONANIM BİLGİLERİ"

safe_cmd "Linux dağıtım ve sürüm" cat /etc/os-release 2>/dev/null || cat /etc/*release 2>/dev/null || echo "[BULUNAMADI]"
safe_cmd "Kernel sürümü" uname -a
safe_cmd "Uptime" uptime
safe_cmd "CPU modeli" cat /proc/cpuinfo | grep "model name" | head -1 || echo "[BULUNAMADI]"
safe_cmd "CPU çekirdek sayısı" nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "[BULUNAMADI]"
safe_cmd "CPU fiziksel çekirdek" grep "physical id" /proc/cpuinfo | sort -u | wc -l 2>/dev/null || echo "[BULUNAMADI]"

# ==============================================================================
# 2. RAM VE SWAP
# ==============================================================================
section "2. BELLEK (RAM) VE SWAP KULLANIMI"

safe_cmd "free -h" free -h 2>/dev/null || echo "[BULUNAMADI]"
safe_cmd "/proc/meminfo (Özet)" grep -E "MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree|SwapCached|Dirty|Writeback" /proc/meminfo 2>/dev/null || echo "[BULUNAMADI]"
safe_cmd "Swap kullanımı" swapon --show 2>/dev/null || cat /proc/swaps 2>/dev/null || echo "[BULUNAMADI]"

# ==============================================================================
# 3. DISK KAPASİTESİ VE I/O
# ==============================================================================
section "3. DISK KAPASİTESİ VE I/O"

safe_cmd "df -h (Disk doluluk)" df -h 2>/dev/null || echo "[BULUNAMADI]"
safe_cmd "df -i (Inode)" df -i 2>/dev/null || echo "[BULUNAMADI]"
safe_cmd "lsblk" lsblk 2>/dev/null || echo "[BULUNAMADI]"

# Disk I/O - iostat yoksa /proc/diskstats
if command -v iostat >/dev/null 2>&1; then
    safe_cmd "iostat -x 1 2" iostat -x 1 2 2>/dev/null || echo "[ÇALIŞTIRILAMADI]"
else
    echo "--- iostat (KOMUT BULUNAMADI, /proc/diskstats alternatif) ---"
    cat /proc/diskstats 2>/dev/null || echo "[BULUNAMADI]"
    echo ""
fi

# ==============================================================================
# 4. CPU KULLANIMI (Anlık ve 60 saniyelik örnekleme)
# ==============================================================================
section "4. CPU KULLANIMI"

echo "--- top (tek örnek, 1 sn) ---"
cmd_or_na "top -bn1 2>/dev/null | head -25" || echo "[BULUNAMADI]"
echo ""

echo "--- /proc/stat (ilk örnek) ---"
cat /proc/stat 2>/dev/null | head -5 || echo "[BULUNAMADI]"
echo ""

echo "--- 60 saniyelik CPU örnekleme (5 sn aralıklarla, 12 örnek) ---"
for i in $(seq 1 12); do
    TS=$(date +"%H:%M:%S")
    CPU_IDLE=$(grep '^cpu ' /proc/stat 2>/dev/null | awk '{print $5}')
    CPU_TOTAL=$(grep '^cpu ' /proc/stat 2>/dev/null | awk '{total=0; for(i=2;i<=NF;i++) total+=$i; print total}')
    if [ -n "$CPU_IDLE" ] && [ -n "$CPU_TOTAL" ]; then
        echo "${TS} | CPU idle=${CPU_IDLE} total=${CPU_TOTAL}"
    else
        echo "${TS} | /proc/stat okunamadı"
    fi
    sleep 5
done 2>&1

echo ""
echo "--- En fazla CPU tüketen işlemler (top -bn1) ---"
cmd_or_na "ps -eo pid,ppid,user,%cpu,%mem,command --sort=-%cpu | head -20" || echo "[BULUNAMADI]"

# ==============================================================================
# 5. NOVAGATE-SERVER SERVİSİ VE PROSESİ
# ==============================================================================
section "5. NOVAGATE-SERVER SERVİS DURUMU VE PROSES ANALİZİ"

safe_cmd "systemctl status novagate-server" systemctl status novagate-server --no-pager -l 2>/dev/null || service novagate-server status 2>/dev/null || echo "[SERVİS BULUNAMADI / systemctl yok]"
echo ""

echo "--- novagate-server işlemi (ps) ---"
ps -ef 2>/dev/null | grep -i novagate | grep -v grep || echo "[novagate-server işlemi bulunamadı]"
echo ""

echo "--- Godot server işlemi (ps) ---"
ps -ef 2>/dev/null | grep -i godot | grep -v grep || echo "[Godot işlemi bulunamadı]"
echo ""

echo "--- novagate-server için detaylı süreç bilgisi ---"
NOVAGATE_PID=$(pgrep -f novagate-server 2>/dev/null || pgrep -f godot.*server 2>/dev/null || echo "")
if [ -n "$NOVAGATE_PID" ]; then
    echo "PID: ${NOVAGATE_PID}"
    safe_cmd "ps -o pid,ppid,user,pcpu,pmem,vsz,rss,stat,start,etime,command -p ${NOVAGATE_PID}" ps -o pid,ppid,user,pcpu,pmem,vsz,rss,stat,start,etime,command -p "${NOVAGATE_PID}" 2>/dev/null || echo "[BULUNAMADI]"
    echo ""
    safe_cmd "RSS ve PSS (/proc/${NOVAGATE_PID}/status)" grep -E "VmRSS|VmPSS|VmSize|VmData|VmStk|VmExe|VmLib|Threads" "/proc/${NOVAGATE_PID}/status" 2>/dev/null || echo "[BULUNAMADI]"
    echo ""
    safe_cmd "Proses fd sayısı" ls -1 "/proc/${NOVAGATE_PID}/fd" 2>/dev/null | wc -l || echo "[BULUNAMADI]"
else
    echo "[novagate-server çalışan işlem bulunamadı - PID tespit edilemedi]"
fi

# ==============================================================================
# 6. AĞ VE UDP 7777
# ==============================================================================
section "6. AĞ VE UDP 7777 BAĞLANTI İSTATİSTİKLERİ"

echo "--- /proc/net/udp (UDP soketleri) ---"
cat /proc/net/udp 2>/dev/null || echo "[BULUNAMADI]"
echo ""

echo "--- /proc/net/udp6 (UDPv6 soketleri) ---"
cat /proc/net/udp6 2>/dev/null || echo "[BULUNAMADI]"
echo ""

if command -v ss >/dev/null 2>&1; then
    safe_cmd "ss -ulnp (UDP dinleyen soketler)" ss -ulnp 2>/dev/null || echo "[ÇALIŞTIRILAMADI]"
    safe_cmd "ss -s (Ağ özet istatistikleri)" ss -s 2>/dev/null || echo "[ÇALIŞTIRILAMADI]"
else
    echo "[ss komutu bulunamadı]"
fi

if command -v netstat >/dev/null 2>&1; then
    safe_cmd "netstat -su (UDP istatistikleri)" netstat -su 2>/dev/null || echo "[ÇALIŞTIRILAMADI]"
else
    echo "[netstat komutu bulunamadı]"
fi

echo "--- UDP 7777 port kontrolü (/proc/net/udp ile) ---"
# 7777 desimal = 0x1E61 hex
grep -i "1E61" /proc/net/udp 2>/dev/null && echo "UDP 7777 dinleniyor ( /proc/net/udp )" || echo "UDP 7777 /proc/net/udp'de bulunamadı (veya okunamadı)"
grep -i "1E61" /proc/net/udp6 2>/dev/null && echo "UDP 7777 dinleniyor ( /proc/net/udp6 )" || echo "UDP 7777 /proc/net/udp6'de bulunamadı (veya okunamadı)"
echo ""

echo "--- Ağ arayüzleri ve RX/TX (cat /proc/net/dev) ---"
cat /proc/net/dev 2>/dev/null || echo "[BULUNAMADI]"
echo ""

if command -v ifconfig >/dev/null 2>&1; then
    safe_cmd "ifconfig" ifconfig 2>/dev/null || echo "[ÇALIŞTIRILAMADI]"
elif command -v ip >/dev/null 2>&1; then
    safe_cmd "ip -s link" ip -s link 2>/dev/null || echo "[ÇALIŞTIRILAMADI]"
else
    echo "[Ağ arayüz komutu bulunamadı]"
fi

echo ""
echo "--- Ağ hataları ve paket düşmesi (/proc/net/snmp) ---"
cat /proc/net/snmp 2>/dev/null | head -20 || echo "[BULUNAMADI]"

# ==============================================================================
# 7. CPU KREDİ VE THROTTLING (T3/T2 instance ipuçları)
# ==============================================================================
section "7. CPU KREDİ VE THROTTLING İPUÇLARI (T3/T2 v.b.)"

echo "--- /proc/stat cpu zamanları (throttling ipucu için) ---"
cat /proc/stat 2>/dev/null | head -5 || echo "[BULUNAMADI]"
echo ""

echo "--- CPU throttling / cgroup bilgisi (varsa) ---"
cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us 2>/dev/null && echo "CPU cfs_quota_us okundu" || echo "[cpu.cfs_quota_us bulunamadı / cgroup v1 yok]"
cat /sys/fs/cgroup/cpu/cpu.cfs_period_us 2>/dev/null && echo "CPU cfs_period_us okundu" || echo "[cpu.cfs_period_us bulunamadı]"
cat /sys/fs/cgroup/cpu/cpu.stat 2>/dev/null | grep -E "nr_throttled|throttled_time" || echo "[cpu.stat throttling bilgisi yok]"
echo ""

echo "--- Load average (1, 5, 15 dk) ---"
cat /proc/loadavg 2>/dev/null || echo "[BULUNAMADI]"
echo ""

echo "--- Context switches ve interrupts ---"
cat /proc/stat 2>/dev/null | grep -E "ctxt|intr" | head -5 || echo "[BULUNAMADI]"

# CloudWatch kontrolü yok (AWS CLI yok / izin yok) - not düşülüyor
echo ""
echo "[NOT: AWS CloudWatch CPU kredi metriklerine erişim için AWS CLI ve kimlik bilgileri gereklidir. Bu script yerel metriklerle sınırlıdır.]"

# ==============================================================================
# 8. SISTEM HATALARI VE LOG KAYITLARI
# ==============================================================================
section "8. SON SİSTEM VE OYUN SUNUCUSU HATA KAYITLARI"

echo "--- dmesg (son 50 satır) ---"
dmesg 2>/dev/null | tail -50 || echo "[dmesg erişilemiyor / yetki yok]"
echo ""

echo "--- journalctl (son sistem hataları, 2 saat) ---"
if command -v journalctl >/dev/null 2>&1; then
    journalctl --no-pager -p err --since "2 hours ago" 2>/dev/null | tail -80 || echo "[journalctl hatası / erişilemiyor]"
else
    echo "[journalctl komutu yok]"
fi
echo ""

echo "--- OOM Killer kayıtları (dmesg / var/log) ---"
dmesg 2>/dev/null | grep -i -E "oom|out of memory|killed process" | tail -20 || echo "[OOM kaydı bulunamadı / dmesg erişilemiyor]"
grep -i -E "oom|out of memory|killed process" /var/log/syslog 2>/dev/null | tail -10 || echo "[/var/log/syslog yok veya OOM kaydı yok]"
grep -i -E "oom|out of memory|killed process" /var/log/messages 2>/dev/null | tail -10 || echo "[/var/log/messages yok veya OOM kaydı yok]"
echo ""

echo "--- novagate-server / Godot log dosyaları (araşındır) ---"
for logfile in \
    /var/log/novagate-server.log \
    /var/log/novagate/server.log \
    /var/log/godot-server.log \
    /home/*/novagate-server.log \
    /home/*/server.log \
    ./server_godot.log \
    ./server_godot*.log \
    ./novagate-server.log; do
    if [ -f "$logfile" ]; then
        echo ">>> $logfile (son 40 satır)"
        tail -40 "$logfile" 2>/dev/null || echo "[okunamadı]"
        echo ""
    fi
done

echo "--- Sunucu başlangıç süresi ve yeniden başlatma ---"
who -b 2>/dev/null || echo "[BULUNAMADI]"
last -x reboot 2>/dev/null | head -5 || echo "[BULUNAMADI]"

# ==============================================================================
# 9. PROCESS AĞ BAĞLANTILARI (novagate-server'a özel)
# ==============================================================================
section "9. NOVAGATE-SERVER PROSES AĞ BAĞLANTILARI"

NOVAGATE_PID=$(pgrep -f novagate-server 2>/dev/null || pgrep -f godot.*server 2>/dev/null || echo "")
if [ -n "$NOVAGATE_PID" ]; then
    echo "--- PID ${NOVAGATE_PID} için ağ bağlantılarını dinlemeye çalışma ---"
    if command -v ss >/dev/null 2>&1; then
        ss -tulpn | grep "${NOVAGATE_PID}" 2>/dev/null || echo "[PID'ye ait aktif soket bulunamadı / erişilemiyor]"
    else
        echo "[ss yok, /proc/${NOVAGATE_PID}/net/udp denenecek]"
        cat "/proc/${NOVAGATE_PID}/net/udp" 2>/dev/null || echo "[/proc/${NOVAGATE_PID}/net/udp erişilemiyor]"
        cat "/proc/${NOVAGATE_PID}/net/udp6" 2>/dev/null || echo "[/proc/${NOVAGATE_PID}/net/udp6 erişilemiyor]"
    fi
else
    echo "[novagate-server PID bulunamadı]"
fi

# ==============================================================================
# RAPOR BİTİŞİ
# ==============================================================================

section "RAPOR BİTİŞİ"
echo "Rapor tamamlandı: ${REPORT_FILE}"
echo "Tarih/Saat: $(date)"

} > "$REPORT_FILE" 2>&1

echo "Diagnostic raporu oluşturuldu: ${REPORT_FILE}"
echo "İçeriği görüntülemek için: cat ${REPORT_FILE}"