#!/bin/bash

# === KONFIGURASI ===
USERNAME="vitacimin"
PASSWORD="akuganteng"
BASE_PORT=3128

# === Telegram Bot Info ===
BOT_TOKEN="7735280430:AAEtpd0qVq2eOzeDqGGesrtxC5XcKlpF-eM"
CHAT_ID="541900896"

WORKDIR="squid-proxy"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# === 1. Ambil Semua IP Publik (kecuali localhost) ===
IP_LIST=($(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -Ev "^(127\.|10\.|172\.|192\.)"))
if [ ${#IP_LIST[@]} -eq 0 ]; then
  echo "❌ Tidak ditemukan IP publik."
  exit 1
fi

# === 2. Buat Dockerfile ===
cat > Dockerfile <<EOF
FROM ubuntu:22.04

RUN apt update && apt install -y squid apache2-utils && rm -rf /var/lib/apt/lists/*

COPY squid.conf /etc/squid/squid.conf
COPY passwd /etc/squid/passwd

CMD ["squid", "-N", "-d", "1"]
EOF

# === 3. Generate squid.conf ===
> squid.conf  # kosongkan dulu
PORT=$BASE_PORT

for IP in "${IP_LIST[@]}"; do
  echo "http_port $IP:$PORT" >> squid.conf
  PORT=$((PORT + 1))
done

cat >> squid.conf <<EOF

auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic realm ProxyAuth
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all

access_log /var/log/squid/access.log
EOF

# === 4. Buat file passwd (hash password) ===
HASH=$(openssl passwd -apr1 "$PASSWORD")
echo "$USERNAME:$HASH" > passwd

# === 5. Build Docker ===
docker build -t squid-proxy .

# === 6. Run Docker dengan Semua Port Terbuka ===
docker rm -f squid-proxy-instance >/dev/null 2>&1

# Buat string -p port1:port1 -p port2:port2 dst
PORT=$BASE_PORT
PORT_ARGS=""
for IP in "${IP_LIST[@]}"; do
  PORT_ARGS="$PORT_ARGS -p $PORT:$PORT"
  PORT=$((PORT + 1))
done

eval docker run -d --name squid-proxy-instance $PORT_ARGS squid-proxy

# === 7. Kirim semua proxy link ke Telegram ===
PORT=$BASE_PORT
PROXY_MESSAGE="✅ *Proxy HTTP Siap Dipakai:*\n\`\`\`"
for IP in "${IP_LIST[@]}"; do
  LINK="http://$USERNAME:$PASSWORD@$IP:$PORT"
  PROXY_MESSAGE+=$'\n'"$LINK"
  PORT=$((PORT + 1))
done
PROXY_MESSAGE+="\n\`\`\`"

# Escape untuk MarkdownV2 Telegram
ESCAPED_MSG=$(echo "$PROXY_MESSAGE" | sed -e 's/\./\\./g' -e 's/\-/\\-/g' -e 's/\//\\\//g' -e 's/@/\\@/g' -e 's/:/\\:/g')

curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
     -d "chat_id=$CHAT_ID" \
     -d "text=$ESCAPED_MSG" \
     -d "parse_mode=MarkdownV2" &&
  echo "✅ Proxy berhasil dikirim ke Telegram" ||
  echo "❌ Gagal mengirim proxy ke Telegram"
