#!/usr/bin/env bash
# =====================================================================
#  Šachové Orákulum – instalace na vlastní server s Caddy (bez Supabase)
#  Stejný příkaz slouží i k aktualizaci – heslo i data zůstanou.
#  Spuštění (jako root):
#    bash <(curl -fsSL https://raw.githubusercontent.com/hensnn/sachove-orakulum/main/install-caddy.sh)
# =====================================================================
set -euo pipefail

WEB=/var/www/html
REPO=https://raw.githubusercontent.com/hensnn/sachove-orakulum/main

echo "♞ 1/6 Instaluji PHP…"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq php-fpm php-cli curl >/dev/null
SOCK=$(ls /run/php/php*-fpm.sock 2>/dev/null | head -1 || true)
if [ -z "$SOCK" ]; then
  systemctl restart "$(systemctl list-unit-files 'php*-fpm.service' --no-legend | awk '{print $1}' | head -1)"
  sleep 2
  SOCK=$(ls /run/php/php*-fpm.sock | head -1)
fi
echo "   PHP běží na $SOCK"

echo "♞ 2/6 Stahuji stránku…"
mkdir -p "$WEB/data"
# při aktualizaci si zapamatuj stávající heslo
OLDPIN=""
[ -f "$WEB/api.php" ] && OLDPIN=$(sed -n "s/^const PIN  = '\\([^']*\\)';.*/\\1/p" "$WEB/api.php" | head -1)
curl -fsSL "$REPO/index.html" -o "$WEB/index.html"
curl -fsSL "$REPO/api.php"    -o "$WEB/api.php"

echo "♞ 3/6 Heslo pro zápis"
if [ -n "$OLDPIN" ]; then
  PIN="$OLDPIN"
  echo "   Ponechávám stávající heslo."
else
while true; do
  read -r -p "   Zadej heslo (písmena, čísla, pomlčky): " PIN
  if [[ "$PIN" =~ ^[A-Za-z0-9_.-]+$ ]]; then break; fi
  echo "   Jen písmena bez diakritiky, čísla, tečka, pomlčka nebo podtržítko. Zkus znovu."
done
fi
sed -i "s/^const PIN  = '';/const PIN  = '$PIN';/" "$WEB/api.php"

echo "♞ 4/6 Připravuji úložiště dat…"
if [ -s "$WEB/data/sachy.json" ]; then
  echo "   Data už existují – nechávám je být."
else
  echo '{"settings":{"stake":100},"players":[],"games":[]}' > "$WEB/data/sachy.json"
  echo "   Založen prázdný data/sachy.json"
fi
chown -R www-data:www-data "$WEB/data"
chmod 750 "$WEB/data"

echo "♞ 5/6 Nastavuji Caddy…"
if [ -f /etc/caddy/Caddyfile ] && grep -q "php_fastcgi" /etc/caddy/Caddyfile; then
  echo "   Caddyfile už PHP obsahuje – nechávám ho být (aktualizace)."
else
  [ -f /etc/caddy/Caddyfile ] && cp /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.zaloha-$(date +%Y%m%d-%H%M%S)"
  cat > /etc/caddy/Caddyfile <<EOF
# Šachové Orákulum – Caddy za Nginx Proxy Managerem (HTTPS řeší NPM)
:80 {
        root * $WEB

        # Datový soubor nikdo nestáhne napřímo, jen přes api.php
        respond /data/* 403

        # PHP pro api.php
        php_fastcgi unix/$SOCK

        file_server
}
EOF
  caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null
  # Caddy musí smět mluvit s PHP (socket patří skupině www-data)
  id caddy >/dev/null 2>&1 && usermod -aG www-data caddy
  systemctl restart caddy
fi

echo "♞ 6/6 Kontrola…"
sleep 1
if curl -fsS http://127.0.0.1/api.php | grep -q '"players"'; then
  echo
  echo "✅ Hotovo! Šachy běží na http://$(hostname -I | awk '{print $1}')/"
  echo "   Heslo pro zápis: $PIN  (změníš v $WEB/api.php)"
  echo "   Data: $WEB/data/sachy.json (zálohuj si ho občas)"
else
  echo "❌ api.php neodpovídá. Pošli výpis: journalctl -u caddy -n 30 --no-pager"
  exit 1
fi
