#!/bin/bash
# #########################################################
# #                                                       # #
# #       Xray + Dante -  VPN/SOCKS5                     # #
# #         ( )                                          # #
# #                                                       # #
# #   VPN                                                 # #
# #   :                                                   # #
# #   -  Xray-core                                       # #
# #   - Reality  Epic Games                               # #
# #   - Dante SOCKS5  (v1.4.4)                           # #
# #   -                                                 # #
# #   - Enterprise-grade                                 # #
# #   -  systemd                                         # #
# #   -  Ubuntu/Debian  amd64/arm64                     # #
# #   -                                                 # #
# #   -                                                 # #
# #                                                       # #
# #   :                                                  # #
# #    - RAM:  1GB                                       # #
# #    - CPU: 1                                          # #
# #    - : x86_64, aarch64                               # #
# #    - : Ubuntu 20.04+, Debian 11+                     # #
# #                                                       # #
# #        : 2025-10-03                                  # #
# #        Xray 25.9.11+  | Dante 1.4.4                  # #
# #########################################################

set -euo pipefail

# ---------- colors ----------
ColorTime='\033[38;5;214m'
ColorReset='\033[0m'
ColorGreen='\033[38;5;82m'
ColorBlue='\033[38;5;33m'
ColorOrange='\033[38;5;208m'
ColorCyan='\033[38;5;45m'
ColorRed='\033[38;5;196m'
ColorYellow='\033[38;5;220m'
ColorMagenta='\033[38;5;201m'
ColorGray='\033[38;5;240m'
ColorPurple='\033[38;5;93m'
ColorPurpleDim='\033[38;5;183m'
ColorGreenDim='\033[38;5;113m'
ColorBlueDim='\033[38;5;67m'
ColorOrangeDim='\033[38;5;215m'
ColorCyanDim='\033[38;5;81m'
ColorRedDim='\033[38;5;210m'
ColorYellowDim='\033[38;5;227m'
ColorWhite='\033[38;5;255m'
ColorGrayDim='\033[38;5;248m'

# ---------- tiny logger ----------
log_message() { printf "%b[%s]%b %b%s%b\n" "$ColorGrayDim" "$(date +'%F %T')" "$ColorReset" "$1" "$2" "$ColorReset"; }
print_step()    { ((++STEP_COUNTER)); log_message "${ColorBlue}[STEP ${STEP_COUNTER}]${ColorReset}" "$1"; }
print_info()    { log_message "${ColorCyan}[INFO]${ColorReset}" "$1"; }
print_success() { log_message "${ColorGreen}[OK]${ColorReset}" "$1"; }
print_warning() { log_message "${ColorYellow}[WARN]${ColorReset}" "$1"; }
print_error()   { log_message "${ColorRed}[ERR ]${ColorReset}" "$1"; }

error_handler() {
  local line_number=$1
  local command="$2"
  log_message "${ColorRed}[ERROR]${ColorReset}" "${ColorRedDim} line $line_number : $command${ColorReset}"
  exit 1
}
trap 'error_handler ${LINENO} "$BASH_COMMAND"' ERR

STEP_COUNTER=0

# ---------- prereqs ----------
print_step "1: Подготовка окружения"
print_info "Обновляю пакеты, ставлю утилиты (curl, jq, qrencode и т.п.)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y > /dev/null 2>&1 || true
apt-get install -y curl jq qrencode ca-certificates > /dev/null 2>&1 || true

print_info "DNS 1.1.1.1 (на случай проблем)"
if grep -q '^nameserver ' /etc/resolv.conf 2>/dev/null; then
  sed -i '1i nameserver 1.1.1.1' /etc/resolv.conf || true
fi

# ---------- Xray-core ----------
print_step "5: Установка Xray-core"    # номер шага согласно исходнику
print_info "Ставлю Xray через официальный установщик."
if ! bash -c "$(curl -sS -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install > /dev/null 2>&1; then
  print_error "Установка Xray-core"
  exit 1
fi
print_success "Xray-core установлен"

# ---------- keys & config ----------
print_step "6: Генерация ключей и UUID"
print_info "Создаю /usr/local/etc/xray и .keys"
mkdir -p /usr/local/etc/xray
touch /usr/local/etc/xray/.keys

# UUID  (xray uuid)  — :contentReference[oaicite:1]{index=1}
uuid_generated=$(xray uuid 2>/dev/null || echo "")
if [ -z "$uuid_generated" ]; then
  print_error "Не удалось сгенерировать UUID"
  exit 1
fi

# x25519 (Reality, Xray 25.9.11+) — поля PrivateKey/Password в выводе  :contentReference[oaicite:2]{index=2}
x25519_output=$(xray x25519 2>/dev/null || true)
if [ -z "$x25519_output" ]; then
  print_error "Не удалось выполнить xray x25519"
  exit 1
fi

# PrivateKey / PublicKey (Password) — как было в исходнике  :contentReference[oaicite:3]{index=3}
privkey=$(echo "$x25519_output" | grep "PrivateKey:" | awk '{print $2}' | tr -d '\r\n')
pubkey=$(  echo "$x25519_output" | grep "Password:"   | awk '{print $2}' | tr -d '\r\n')
if [ -z "$privkey" ] || [ -z "$pubkey" ]; then
  print_error "Парсинг x25519 вывода"
  print_info  "raw: $x25519_output"
  exit 1
fi

print_info "PrivateKey: ${privkey:0:20}..."
print_info "PublicKey:  ${pubkey:0:20}..."

# shortsid  — :contentReference[oaicite:4]{index=4}
shortsid_generated=$(openssl rand -hex 8 2>/dev/null || echo "")
if [ -z "$shortsid_generated" ]; then
  print_error "Генерация shortsid"
  exit 1
fi

# .keys — :contentReference[oaicite:5]{index=5}
cat > /usr/local/etc/xray/.keys <<KEYS_EOF
uuid: $uuid_generated
privateKey: $privkey
publicKey: $pubkey
shortsid: $shortsid_generated
KEYS_EOF
print_success ".keys создан"
print_info "UUID: $uuid_generated"
print_info "ShortSID: $shortsid_generated"

# ---------- config.json (Reality + Epic Games SNI) ----------
print_step "7: Настройка Xray (Reality)"
print_info "Пишу /usr/local/etc/xray/config.json с Reality (epicgames.com)."

cat > /usr/local/etc/xray/config.json <<'CONFIG_EOF'
{
  "log": { "loglevel": "warning" },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "domain": [
          "geosite:category-ads-all",
          "ext:adlist.dat:hagezi-pro",
          "ext:adblock.dat:adblock"
        ],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "ip": ["geoip:cn"],
        "outboundTag": "block"
      }
    ]
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "email": "main",
            "id": "UUID_PLACEHOLDER",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "epicgames.com:443",
          "xver": 0,
          "serverNames": [
            "epicgames.com",
            "store.epicgames.com",
            "launcher-public-service-prod06.ol.epicgames.com",
            "download.epicgames.com"
          ],
          "privateKey": "PRIVKEY_PLACEHOLDER",
          "minClientVer": "",
          "maxClientVer": "",
          "maxTimeDiff": 0,
          "shortIds": [ "SHORTSID_PLACEHOLDER" ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http","tls"]
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom",   "tag": "direct" },
    { "protocol": "blackhole", "tag": "block"  }
  ],
  "policy": {
    "levels": {
      "0": { "handshake": 3, "connIdle": 180 }
    }
  }
}
CONFIG_EOF
# Подстановка значений из .keys (как в исходнике) — :contentReference[oaicite:6]{index=6}
jq --arg uuid   "$uuid_generated" \
   --arg pk     "$privkey" \
   --arg sid    "$shortsid_generated" \
   '.inbounds[0].settings.clients[0].id = $uuid
  |.inbounds[0].streamSettings.realitySettings.privateKey = $pk
  |.inbounds[0].streamSettings.realitySettings.shortIds   = [$sid]' \
   /usr/local/etc/xray/config.json > /tmp/config.tmp && mv /tmp/config.tmp /usr/local/etc/xray/config.json

print_success "config.json создан"

# ---------- вспомогательные скрипты ----------
print_step "8: Вспомогательные утилиты (userlist, mainuser, newuser, rmuser, sharelink, changesni)"
print_info "Устанавливаю скрипты: userlist, mainuser, newuser, rmuser, sharelink, changesni."  # :contentReference[oaicite:7]{index=7}

# userlist — 
cat > /usr/local/bin/userlist <<'USERLIST_EOF'
#!/bin/bash
emails=($(jq -r '.inbounds[0].settings.clients[].email' "/usr/local/etc/xray/config.json"))
if [[ ${#emails[@]} -eq 0 ]]; then
    echo "Список пуст"
    exit 1
fi
echo "Пользователи:"
for i in "${!emails[@]}"; do
    echo "$((i+1)). ${emails[$i]}"
done
USERLIST_EOF
chmod +x /usr/local/bin/userlist

# mainuser — 
cat > /usr/local/bin/mainuser <<'MAINUSER_EOF'
#!/bin/bash
ColorReset='\033[0m'
ColorOrange='\033[38;5;208m'
ColorCyan='\033[38;5;45m'
ColorYellow='\033[38;5;220m'
ColorWhite='\033[38;5;255m'
ColorGrayDim='\033[38;5;248m'
ColorRed='\033[38;5;196m'
protocol=$(jq -r '.inbounds[0].protocol' /usr/local/etc/xray/config.json)
port=$(jq -r '.inbounds[0].port' /usr/local/etc/xray/config.json)
uuid=$(awk -F': ' '/^uuid:/ {print $2}' /usr/local/etc/xray/.keys | tr -d ' ')
pbk=$(awk -F': ' '/^publicKey:/ {print $2}' /usr/local/etc/xray/.keys | tr -d ' ')
sid=$(awk -F': ' '/^shortsid:/ {print $2}' /usr/local/etc/xray/.keys | tr -d ' ')
sni=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' /usr/local/etc/xray/config.json)
ip=$(timeout 3 curl -4 icanhazip.com || hostname -I | awk '{print $1}')
if [ -z "$uuid" ] || [ -z "$pbk" ] || [ -z "$sid" ] || [ -z "$ip" ]; then
    echo -e "${ColorRed}Данные неполные${ColorReset}"
    echo -e "${ColorGrayDim}UUID: $uuid${ColorReset}"
    echo -e "${ColorGrayDim}PublicKey: $pbk${ColorReset}"
    echo -e "${ColorGrayDim}ShortID: $sid${ColorReset}"
    echo -e "${ColorGrayDim}IP: $ip${ColorReset}"
    exit 1
fi
link="$protocol://$uuid@$ip:$port?security=reality&sni=$sni&fp=firefox&pbk=$pbk&sid=$sid&spx=/&type=tcp&flow=xtls-rprx-vision&encryption=none#main-user"
echo -e "\n${ColorOrange}Ваш основной VPN доступ${ColorReset}"
echo -e "${ColorCyan}Ссылка (клиенты: v2rayNG/v2rayN/Shadowrocket и др.)${ColorReset}"
echo -e "${ColorYellow}${link}${ColorReset}\n"
echo -e "${ColorCyan}${ColorWhite}QR-код:${ColorReset}\n"
if command -v qrencode >/dev/null 2>&1; then
    echo -n "${link}" | qrencode -t ansiutf8
else
    echo -e "qrencode не найден — QR не будет показан"
fi
echo
MAINUSER_EOF
chmod +x /usr/local/bin/mainuser

# newuser — :contentReference[oaicite:10]{index=10}
cat > /usr/local/bin/newuser <<'NEWUSER_EOF'
#!/bin/bash
read -p "Email нового пользователя: " email
if [[ -z "$email" ]]; then
    echo "Email пуст"
    exit 1
fi
user_json=$(jq --arg email "$email" '.inbounds[0].settings.clients[] | select(.email == $email)' /usr/local/etc/xray/config.json)
if [[ -z "$user_json" ]]; then
    uuid=$(xray uuid)
    jq --arg email "$email" --arg uuid "$uuid" '.inbounds[0].settings.clients += [{"email": $email, "id": $uuid, "flow": "xtls-rprx-vision"}]' /usr/local/etc/xray/config.json > tmp.json && mv tmp.json /usr/local/etc/xray/config.json
    systemctl restart xray
    index=$(jq --arg email "$email" '.inbounds[0].settings.clients | to_entries[] | select(.value.email == $email) | .key' /usr/local/etc/xray/config.json)
    protocol=$(jq -r '.inbounds[0].protocol' /usr/local/etc/xray/config.json)
    port=$(jq -r '.inbounds[0].port' /usr/local/etc/xray/config.json)
    uuid=$(jq --argjson index "$index" -r '.inbounds[0].settings.clients[$index].id' /usr/local/etc/xray/config.json)
    pbk=$(awk -F': ' '/^publicKey:/ {print $2}' /usr/local/etc/xray/.keys | tr -d ' ')
    sid=$(awk -F': ' '/^shortsid:/ {print $2}' /usr/local/etc/xray/.keys | tr -d ' ')
    username=$(jq --argjson index "$index" -r '.inbounds[0].settings.clients[$index].email' /usr/local/etc/xray/config.json)
    sni=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' /usr/local/etc/xray/config.json)
    ip=$(timeout 3 curl -4 icanhazip.com || hostname -I | awk '{print $1}')
    link="$protocol://$uuid@$ip:$port?security=reality&sni=$sni&fp=firefox&pbk=$pbk&sid=$sid&spx=/&type=tcp&flow=xtls-rprx-vision&encryption=none#$username"
    echo ""
    echo "Ссылка для $email:"
    echo "$link"
    echo ""
    echo "QR:"
    echo "${link}" | qrencode -t ansiutf8 2>/dev/null || echo "qrencode не установлен"
else
    echo "Такой email уже есть"
fi
NEWUSER_EOF
chmod +x /usr/local/bin/newuser

# rmuser — :contentReference[oaicite:11]{index=11}
cat > /usr/local/bin/rmuser <<'RMUSER_EOF'
#!/bin/bash
emails=($(jq -r '.inbounds[0].settings.clients[].email' "/usr/local/etc/xray/config.json"))
if [[ ${#emails[@]} -eq 0 ]]; then
    echo "Список пуст"
    exit 1
fi
echo "Выберите пользователя:"
for i in "${!emails[@]}"; do
    echo "$((i+1)). ${emails[$i]}"
done
read -p "Номер: " choice
if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#emails[@]} )); then
    echo "Неверный выбор (1..${#emails[@]})"
    exit 1
fi
selected_email="${emails[$((choice - 1))]}"
jq --arg email "$selected_email" '(.inbounds[0].settings.clients) |= map(select(.email != $email))' "/usr/local/etc/xray/config.json" > tmp && mv tmp "/usr/local/etc/xray/config.json"
systemctl restart xray
echo "Удален: $selected_email"
RMUSER_EOF
chmod +x /usr/local/bin/rmuser

# sharelink — :contentReference[oaicite:12]{index=12}
cat > /usr/local/bin/sharelink <<'SHARELINK_EOF'
#!/bin/bash
emails=($(jq -r '.inbounds[0].settings.clients[].email' /usr/local/etc/xray/config.json))
if [[ ${#emails[@]} -eq 0 ]]; then
    echo "Список пуст"
    exit 1
fi
echo "Выберите пользователя:"
for i in "${!emails[@]}"; do
   echo "$((i + 1)). ${emails[$i]}"
done
read -p "Номер: " client
if ! [[ "$client" =~ ^[0-9]+$ ]] || (( client < 1 || client > ${#emails[@]} )); then
    echo "Неверный выбор (1..${#emails[@]})"
    exit 1
fi
selected_email="${emails[$((client - 1))]}"
index=$(jq --arg email "$selected_email" '.inbounds[0].settings.clients | to_entries[] | select(.value.email == $email) | .key' /usr/local/etc/xray/config.json)
protocol=$(jq -r '.inbounds[0].protocol' /usr/local/etc/xray/config.json)
port=$(jq -r '.inbounds[0].port' /usr/local/etc/xray/config.json)
uuid=$(jq --argjson index "$index" -r '.inbounds[0].settings.clients[$index].id' /usr/local/etc/xray/config.json)
pbk=$(awk -F': ' '/^publicKey:/ {print $2}' /usr/local/etc/xray/.keys | tr -d ' ')
sid=$(awk -F': ' '/^shortsid:/ {print $2}' /usr/local/etc/xray/.keys | tr -d ' ')
username=$(jq --argjson index "$index" -r '.inbounds[0].settings.clients[$index].email' /usr/local/etc/xray/config.json)
sni=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' /usr/local/etc/xray/config.json)
ip=$(timeout 3 curl -4 icanhazip.com || hostname -I | awk '{print $1}')
link="$protocol://$uuid@$ip:$port?security=reality&sni=$sni&fp=firefox&pbk=$pbk&sid=$sid&spx=/&type=tcp&flow=xtls-rprx-vision&encryption=none#$username"
echo ""
echo "Ссылка ($username):"
echo "$link"
echo ""
echo "QR:"
echo "${link}" | qrencode -t ansiutf8 2>/dev/null || echo "qrencode не установлен"
SHARELINK_EOF
chmod +x /usr/local/bin/sharelink

# changesni — 
cat > /usr/local/bin/changesni <<'CHANGESNI_EOF'
#!/bin/bash
if [[ $EUID -ne 0 ]]; then
   echo "Запусти как root (sudo)"
   exit 1
fi
if [ -z "$1" ]; then
    echo "Использование: changesni <main.sni> [extra1 extra2 ...]"
    echo "Примеры:"
    echo "  changesni github.com"
    echo "  changesni epicgames.com store.epicgames.com"
    echo ""
    echo "Текущие SNI:"
    jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[]' /usr/local/etc/xray/config.json
    exit 1
fi
main_sni="$1"
shift
additional_snis=("$@")
if ! [[ "$main_sni" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo "main_sni некорректен"
    exit 1
fi
config_file="/usr/local/etc/xray/config.json"
sni_array="[\"$main_sni\""
for sni in "${additional_snis[@]}"; do
    sni_array+=",\"$sni\""
done
sni_array+="]"
jq --arg dest "$main_sni:443" --argjson snis "$sni_array" \
   '.inbounds[0].streamSettings.realitySettings.serverNames = $snis |
    .inbounds[0].streamSettings.realitySettings.dest = $dest' \
   "$config_file" > /tmp/config.tmp && mv /tmp/config.tmp "$config_file"
if systemctl restart xray; then
    echo "SNI обновлён, Xray перезапущен."
    echo ""
    echo "Актуальные SNI:"
    jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[]' "$config_file"
else
    echo "Ошибка перезапуска Xray"
    exit 1
fi
CHANGESNI_EOF
chmod +x /usr/local/bin/changesni
print_success "Утилиты установлены"

# ---------- (закомментировано) Dante SOCKS5 ----------
# 9:  Dante SOCKS5 — весь блок умышленно закомментирован в исходнике  :contentReference[oaicite:14]{index=14}
# print_step "9: Dante SOCKS5"
# print_info "Проверяю установлен ли dante-server / danted"
# dante_installed=false
# if dpkg -l | grep -q "^ii.*dante-server"; then
#     print_warning "Найден пакет dante-server"
#     dante_installed=true
# fi
# if [ "$dante_installed" = false ] && [ -f "/usr/sbin/danted" ]; then
#     if /usr/sbin/danted -v > /dev/null 2>&1; then
#         dante_version=$(/usr/sbin/danted -v 2>&1 | head -n1)
#         print_warning "Найден установленный Dante: $dante_version"
#         dante_installed=true
#     fi
# fi
# if [ "$dante_installed" = true ]; then
#     print_info "Пропускаю сборку Dante"
# else
#     print_info "Готовлю зависимости для сборки..."
#     if ! apt install -y build-essential libwrap0-dev libpam0g-dev libkrb5-dev \
#         libssl-dev libsasl2-dev wget tar pkg-config autotools-dev > /dev/null 2>&1; then
#         print_error "Установка зависимостей Dante"
#         exit 1
#     fi
#     print_success "Deps OK"
#     build_dir="/tmp/dante-build"; rm -rf "$build_dir"; mkdir -p "$build_dir"
#     print_info "Скачиваю dante-1.4.4.tar.gz..."
#     if ! wget -q https://www.inet.no/dante/files/dante-1.4.4.tar.gz -P "$build_dir"; then
#         print_error "Загрузка dante-1.4.4"
#         exit 1
#     fi
#     print_info "Распаковываю и собираю..."
#     if ! tar -C "$build_dir" -xzf "$build_dir/dante-1.4.4.tar.gz"; then exit 1; fi
#     cd "$build_dir/dante-1.4.4"
#     ./configure --prefix=/usr --sysconfdir=/etc --without-libminiupnpc --enable-client=no
#     make -j"$(nproc)"; make install
# fi
# print_success "Dante установлен"
# print_info "Пишу /etc/danted.conf ..."
# cat > /etc/danted.conf <<'DANTE_CONFIG_EOF'
# logoutput: syslog /var/log/danted.log
# internal: 0.0.0.0 port = 30050
# external: auto
# socksmethod: none
# user.notprivileged: nobody
# client pass {
#     from: 0.0.0.0/0 to: 0.0.0.0/0
#     log: error
# }
# socks pass {
#     from: 0.0.0.0/0 to: 0.0.0.0/0
#     command: connect bind udpassociate bindreply udpreply
#     log: error
# }
# DANTE_CONFIG_EOF
# print_success "Файл /etc/danted.conf создан"
# print_info "Создаю systemd unit для danted..."
# cat > /etc/systemd/system/danted.service <<'DANTE_SERVICE_EOF'
# [Unit]
# Description=Dante SOCKS5 Server
# Documentation=man:danted(8) man:danted.conf(5)
# After=network.target
# [Service]
# Type=simple
# PIDFile=/run/danted.pid
# ExecStartPre=/bin/sleep 10
# ExecStart=/usr/sbin/danted -f /etc/danted.conf
# ExecReload=/bin/kill -HUP $MAINPID
# Restart=on-failure
# RestartSec=5s
# LimitNOFILE=262144
# LimitNPROC=16384
# LimitMEMLOCK=256M
# PrivateTmp=true
# NoNewPrivileges=false
# [Install]
# WantedBy=multi-user.target
# DANTE_SERVICE_EOF
# print_success "Systemd unit для Dante создан"
# print_info "systemd daemon-reload."
# systemctl daemon-reload
# print_info "Запускаю Dante..."
# if ! systemctl start danted > /dev/null 2>&1; then
#     print_error "Запуск Dante"
#     print_info "Смотри: journalctl -u danted -n 50"
#     exit 1
# fi
# print_info "Включаю автозапуск Dante..."
# if ! systemctl enable danted > /dev/null 2>&1; then
#     print_warning "Не удалось включить автозапуск Dante"
# else
#     print_success "Dante включён в автозапуск"
# fi
# sleep 2
# if systemctl is-active --quiet danted; then
#     print_success "Dante работает. SOCKS5 порт 30050"
# else
#     print_error "Dante не запустился"
#     print_info "Проверь: systemctl status danted"
#     exit 1
# fi

# ---------- обновлялка датасетов + автоперезапуск через cron ----------

print_info "Downloading initial ad blocking files"
curl -L https://github.com/zxc-rv/ad-filter/releases/latest/download/adlist.dat -o /usr/local/share/xray/adlist.dat
curl -L https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geosite.dat -o /usr/local/share/xray/geosite.dat
curl -L https://github.com/REIJI007/AdBlock_Rule_For_V2ray/releases/latest/download/adblock.dat -o /usr/local/share/xray/adblock.dat
print_success "Ad blocking files downloaded"

print_step "11: Настройка cron для geosite/adlist/adblock и Xray reinstall"  # номера как в исходнике
print_info "Готовлю каталог /usr/local/share/xray"
mkdir -p /usr/local/share/xray

current_crontab=$(crontab -l 2>/dev/null || echo "")
if echo "$current_crontab" | grep -q "Xray"; then
  print_info "Cron уже содержит наши задания."
else
  print_info "Добавляю задания в crontab."
  new_crontab_content="$current_crontab"
  [ -n "$current_crontab" ] && new_crontab_content="$current_crontab"$'\n'
  # блок из исходника — 
  cat > /tmp/new_cron_jobs <<'CRON_END'
# Xray datasets update
0 4 */3 * * curl -L https://github.com/zxc-rv/ad-filter/releases/latest/download/adlist.dat -o /usr/local/share/xray/adlist.dat > /dev/null 2>&1
5 4 */3 * * curl -L https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geosite.dat -o /usr/local/share/xray/geosite.dat > /dev/null 2>&1
10 4 */3 * * curl -L https://github.com/REIJI007/AdBlock_Rule_For_V2ray/releases/latest/download/adblock.dat -o /usr/local/share/xray/adblock.dat > /dev/null 2>&1
# Xray reinstall (официальный инсталлер)
0 3 */3 * * bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install > /dev/null 2>&1
# Xray periodic restart
25 4 */3 * * systemctl restart xray > /dev/null 2>&1
CRON_END
  new_crontab_content="${new_crontab_content}$(cat /tmp/new_cron_jobs)"
  if echo "$new_crontab_content" | crontab -; then
    print_success "Cron обновлён"
  else
    print_warning "Не удалось применить crontab"
  fi
  rm -f /tmp/new_cron_jobs
fi

# ---------- systemd unit(s) Xray (оба варианта, плюс override) ----------
print_step "Xray systemd units"
print_info "Создаю стандартный /etc/systemd/system/xray.service"
cat > /etc/systemd/system/xray.service <<'UNIT_EOF'
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target
[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000
[Install]
WantedBy=multi-user.target
UNIT_EOF

print_info "Создаю шаблонный /etc/systemd/system/xray@.service (как в исходнике)"
cat > /etc/systemd/system/xray@.service <<'UNIT2_EOF'
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target
[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/%i.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000
[Install]
WantedBy=multi-user.target
UNIT2_EOF

print_info "Создаю override для xray.service — ExecStart= (две версии как в исходнике)"
mkdir -p /etc/systemd/system/xray.service.d
cat > /etc/systemd/system/xray.service.d/override.conf <<'OVR_EOF'
# In case you have a good reason to do so, duplicate this file in the same directory and make your customizes there.
# Or all changes you made will be lost!  # Refer: https://www.freedesktop.org/software/systemd/man/systemd.unit.html
[Service]
ExecStart=
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
OVR_EOF

mkdir -p /etc/systemd/system/xray@.service.d
cat > /etc/systemd/system/xray@.service.d/override.conf <<'OVR2_EOF'
# In case you have a good reason to do so, duplicate this file in the same directory and make your customizes there.
# Or all changes you made will be lost!  # Refer: https://www.freedesktop.org/software/systemd/man/systemd.unit.html
[Service]
ExecStart=
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/%i.json
OVR2_EOF

print_info "Перезапускаю systemd, включаю и запускаю Xray"
systemctl daemon-reload
systemctl enable xray > /dev/null 2>&1 || print_warning "Не удалось включить автозапуск Xray"
systemctl restart xray

sleep 2
if ! systemctl is-active --quiet xray; then
  print_error "Xray не активен"
  print_info "Проверь: systemctl status xray"
  exit 1
fi
print_success "Xray запущен"

# ---------- help ----------
print_info "Пишу $HOME/help с подсказками по командам"
{
echo ""
echo "     XRAY + DANTE"
echo ""
echo "Xray:"
echo "  mainuser   - показать ссылку/QR для основного пользователя"
echo "  newuser    - добавить нового пользователя"
echo "  rmuser     - удалить пользователя"
echo "  sharelink  - вывести ссылку/QR для выбранного пользователя"
echo "  userlist   - список emails"
echo ""
echo "  changesni <main.sni> [extra...]  - сменить SNI (пример: changesni github.com)"
echo ""
echo "Xray:"
echo "  systemctl restart xray  - перезапуск Xray"
echo "  systemctl status xray   - статус Xray"
echo ""
echo "Dante:"
echo "  systemctl restart danted  - перезапуск SOCKS5 (если включен)"
echo "  systemctl status danted   - статус SOCKS5 (если включен)"
echo ""
echo "SOCKS5 порт 30050 (если включен Dante)"
echo ""
echo "Требования: Xray 25.9.11+ | Dante 1.4.4"
} > "$HOME/help"

print_success "Xray + Dante (скрипт) завершил работу"
# ---------- конец ----------
