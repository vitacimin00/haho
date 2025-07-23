#!/bin/bash

# === KONFIGURASI ===
USERNAME="vitacimin"
PASSWORD="akuganteng"
PORT="3128"

# === Telegram Bot Info ===
BOT_TOKEN="7735280430:AAEtpd0qVq2eOzeDqGGesrtxC5XcKlpF-eM"
CHAT_ID="541900896"

WORKDIR="squid-proxy"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# === 1. Buat Dockerfile ===
cat > Dockerfile <<EOF
FROM ubuntu:22.04

RUN apt update && apt install -y squid apache2-utils && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/squid/custom
COPY squid.conf /etc/squid/squid.conf
COPY passwd /etc/squid/passwd

EXPOSE $PORT

CMD ["squid", "-N", "-d", "1"]
EOF

# === 2. Buat konfigurasi squid.conf ===
cat > squid.conf <<EOF
http_port $PORT

auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic realm ProxyAuth
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all

access_log /var/log/squid/access.log
EOF

# === 3. Buat file passwd (dengan htpasswd) ===
htpasswd -b -c passwd "$USERNAME" "$PASSWORD"

# === 4. Build & Run Docker ===
docker build -t squid-proxy .
docker rm -f squid-proxy-instance >/dev/null 2>&1
docker run -d --name squid-proxy-instance -p $PORT:$PORT --restart unless-stopped squid-proxy

# === 5. Ambil IP VPS (paksa IPv4) ===
SERVER_IP=$(curl -4 -s https://ifconfig.me || curl -4 -s https://ipinfo.io/ip)

# === 6. Format link dan escape untuk Telegram MarkdownV2 ===
PROXY_LINK="http://$USERNAME:$PASSWORD@$SERVER_IP:$PORT"
ESCAPED_LINK=$(printf "%s" "$PROXY_LINK" | sed -e 's/[]\/()~#^*+?.|$&!{}[\]:<>@`_=-]/\\&/g')

# === 7. Buat pesan Telegram ===
MESSAGE="✅ Proxy HTTP Siap Dipakai:
\\\`
$ESCAPED_LINK
\\\`"

# === 8. Kirim ke Telegram ===
if curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
     -d "chat_id=$CHAT_ID" \
     -d "text=$MESSAGE" \
     -d "parse_mode=MarkdownV2"; then
  echo "✅ Proxy berhasil dikirim ke Telegram (via chat)"
else
  echo "❌ Gagal mengirim proxy ke Telegram"
fi
