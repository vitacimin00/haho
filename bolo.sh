#!/bin/bash

# === KONFIGURASI ===
USERNAME="vitacimin"
PASSWORD="akuganteng"
PASSWD_FILE="/etc/squid/passwd"
BASE_PORT=3000

# === TELEGRAM CONFIG ===
BOT_TOKEN="7735280430:AAEtpd0qVq2eOzeDqGGesrtxC5XcKlpF-eM"
CHAT_ID="541900896"

# === AMBIL SEMUA IP PUBLIK DARI INTERFACE YANG AKTIF ===
IPS=()
while IFS= read -r ip; do
    if [[ ! $ip =~ ^127\. && ! $ip =~ ^10\. && ! $ip =~ ^192\.168\. && ! $ip =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
        IPS+=("$ip")
    fi
done < <(ip -4 -o addr show up | awk '{print $4}' | cut -d/ -f1 | sort -u)

if (( ${#IPS[@]} == 0 )); then
    echo "❌ Tidak ditemukan IP publik."
    exit 1
fi

# === INSTALL DEPENDENSI ===
apt update -y
apt install -y squid apache2-utils curl

# === BUAT USER AUTH ===
htpasswd -cb $PASSWD_FILE $USERNAME "$PASSWORD"
chmod 640 $PASSWD_FILE
chown proxy:proxy $PASSWD_FILE

# === BUAT KONFIGURASI SQUID ===
cp /etc/squid/squid.conf /etc/squid/squid.conf.bak.$(date +%F-%T)

cat > /etc/squid/squid.conf <<EOF
auth_param basic program /usr/lib/squid/basic_ncsa_auth $PASSWD_FILE
auth_param basic realm Proxy
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all
access_log /var/log/squid/access.log
cache_log /var/log/squid/cache.log
logfile_rotate 10
buffered_logs on
dns_v4_first on
visible_hostname proxy.local
EOF

PORT_LIST=()
PORT=$BASE_PORT

for ip in "${IPS[@]}"; do
    echo "http_port $PORT" >> /etc/squid/squid.conf
    echo "acl toport$PORT myport $PORT" >> /etc/squid/squid.conf
    echo "tcp_outgoing_address $ip toport$PORT" >> /etc/squid/squid.conf
    echo "" >> /etc/squid/squid.conf
    PORT_LIST+=("$ip:$PORT")
    ((PORT++))
done

# === RESTART SQUID ===
systemctl restart squid
if systemctl is-active --quiet squid; then
    echo "✅ Squid berhasil dijalankan."
else
    echo "❌ Squid gagal dijalankan. Periksa dengan: journalctl -xe"
fi

# === OUTPUT FILE ===
PUBLIC_IP_MAIN=$(curl -s ifconfig.me)
FILENAME="proxies-$PUBLIC_IP_MAIN.txt"
> "$FILENAME"
PROXY_LINKS=""

for entry in "${PORT_LIST[@]}"; do
    ip="${entry%%:*}"
    port="${entry##*:}"
    echo "http://$USERNAME:$PASSWORD@$ip:$port" >> "$FILENAME"
    PROXY_LINKS+="http://$USERNAME:$PASSWORD@$ip:$port"$'\n'
done

echo "✅ File $FILENAME selesai dibuat dengan total ${#PORT_LIST[@]} proxy"

# === AUTO RESTART CRON SETIAP 12 JAM ===
CRON_FILE="/etc/cron.d/squid-autorestart"
cat > "$CRON_FILE" <<EOF
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin
0 */12 * * * root systemctl restart squid
EOF
chmod 644 "$CRON_FILE"
echo "🕒 Cron dibuat di $CRON_FILE untuk auto restart tiap 12 jam"

# === ESCAPE DAN KIRIM KE TELEGRAM DENGAN MARKDOWN V2 ===
ESCAPED_LINKS=$(cat "$FILENAME" | sed 's/\./\\./g; s/\-/\\-/g; s/\//\\\//g; s/@/\\@/g; s/:/\\:/g')
MESSAGE=$(cat <<EOF
✅ Proxy HTTP Siap Dipakai:
\`\`\`
$ESCAPED_LINKS
\`\`\`
EOF
)

curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
     -d "chat_id=$CHAT_ID" \
     -d "text=$MESSAGE" \
     -d "parse_mode=MarkdownV2" \
     && echo "✅ Proxy berhasil dikirim ke Telegram" \
     || echo "❌ Gagal mengirim ke Telegram"
