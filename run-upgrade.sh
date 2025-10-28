#!/usr/bin/env bash
set -euo pipefail

# ================================
# Debian 12 -> 13 one-shot upgrade
# ================================

RELEASE_FROM="bookworm"
RELEASE_TO="trixie"
LOG_DIR="/root/upgrade-logs"
BACKUP_DIR="/root/upgrade-backup-$(date +%F_%H-%M-%S)"
DEBIAN_FRONTEND=noninteractive
APT_FLAGS=(-y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold")

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

log() { echo -e "[*] $*"; }
die() { echo -e "[!] $*" >&2; exit 1; }

# --- Предварительные проверки ---
if [[ $EUID -ne 0 ]]; then
  die "Запусти скрипт от root (sudo -i)."
fi

# Проверим, что это Debian
if ! grep -qi 'debian' /etc/os-release; then
  die "Похоже, это не Debian. Прерываю."
fi

# Проверим текущий релиз (допускаем, что могут быть кастомные сборки)
CURRENT_CODENAME="$(. /etc/os-release; echo "${VERSION_CODENAME:-}")"
if [[ -z "${CURRENT_CODENAME}" ]]; then
  CURRENT_CODENAME="$(lsb_release -sc 2>/dev/null || true)"
fi

if [[ -z "${CURRENT_CODENAME}" ]]; then
  die "Не удалось определить VERSION_CODENAME."
fi

log "Текущий релиз: ${CURRENT_CODENAME}"
if [[ "${CURRENT_CODENAME}" != "${RELEASE_FROM}" ]]; then
  log "Внимание: ожидается ${RELEASE_FROM}, а обнаружено ${CURRENT_CODENAME}."
  log "Продолжаю только если это осознанно..."
fi

# Проверим свободное место (минимум ~2 ГБ)
FREE_MB=$(df -Pm / | awk 'NR==2{print $4}')
if (( FREE_MB < 2048 )); then
  die "Мало места на / (${FREE_MB} MB). Освободи ? 2 GB."
fi

# --- Бэкап важных данных ---
log "Делаю бэкап конфигураций и списков пакетов в ${BACKUP_DIR} ..."
cp -a /etc "$BACKUP_DIR/etc"
cp -a /etc/apt "$BACKUP_DIR/etc_apt"
dpkg --get-selections > "$BACKUP_DIR/dpkg-selections.txt" || true
apt-mark showmanual > "$BACKUP_DIR/apt-manual.txt" || true
cp -a /var/lib/dpkg "$BACKUP_DIR/dpkg-db" || true

# --- Обновление текущего Debian 12 ---
log "apt update / full-upgrade на текущем релизе..."
apt update | tee "$LOG_DIR/01-apt-update-pre.log"
apt full-upgrade -y | tee "$LOG_DIR/02-full-upgrade-pre.log"
apt --fix-broken install -y | tee "$LOG_DIR/03-fix-broken-pre.log" || true
apt autoremove -y | tee "$LOG_DIR/04-autoremove-pre.log" || true

# --- Отключаем сторонние репозитории (временно) ---
disable_third_party() {
  local srcd="/etc/apt/sources.list.d"
  [[ -d "$srcd" ]] || return 0
  mkdir -p "$BACKUP_DIR/sources.list.d"
  cp -a "$srcd"/* "$BACKUP_DIR/sources.list.d/" 2>/dev/null || true
  for f in "$srcd"/*.list; do
    [[ -e "$f" ]] || continue
    # Комментируем все строки, кроме официальных зеркал Debian
    if grep -Eq '^(deb|deb-src)\s' "$f"; then
      awk '
        BEGIN{IGNORECASE=1}
        /^#/ {print; next}
        /deb(\-src)?\s/ {
          if ($0 ~ /(deb\.debian\.org|security\.debian\.org)/) { print; }
          else { print "#" $0 "  # disabled temporarily"; }
          next
        }
        {print}
      ' "$f" > "${f}.tmp"
      mv "${f}.tmp" "$f"
    fi
  done
}
log "Отключаю сторонние репозитории (если есть)..."
disable_third_party

# --- Переключаем /etc/apt/sources.list и security на trixie ---
log "Переключаю репозитории на ${RELEASE_TO}..."
cp -a /etc/apt/sources.list "$BACKUP_DIR/sources.list.before"
sed -i "s/${RELEASE_FROM}/${RELEASE_TO}/g" /etc/apt/sources.list || true
# Если встречаются oldstable/stable — нормализуем на trixie
sed -i 's/\boldstable\b/trixie/g;s/\bstable\b/trixie/g' /etc/apt/sources.list || true

# Убеждаемся, что базовые записи присутствуют
ensure_base_repos() {
  local f="/etc/apt/sources.list"
  grep -q "deb .* ${RELEASE_TO} " "$f" || {
cat >> "$f" <<EOF

# Base Debian ${RELEASE_TO}
deb http://deb.debian.org/debian ${RELEASE_TO} main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security ${RELEASE_TO}-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${RELEASE_TO}-updates main contrib non-free non-free-firmware
EOF
  }
}
ensure_base_repos

# --- Обновление индексов и "минимальный" апгрейд ---
log "apt update на ${RELEASE_TO}..."
apt update | tee "$LOG_DIR/05-apt-update-trixie.log"

log "Предварительное обновление (без новых пакетов)..."
apt upgrade --without-new-pkgs -y | tee "$LOG_DIR/06-upgrade-without-newpkgs.log" || true

# --- Полный апгрейд ---
log "Полное обновление до ${RELEASE_TO}..."
apt full-upgrade "${APT_FLAGS[@]}" | tee "$LOG_DIR/07-full-upgrade-trixie.log"

# --- Очистка ---
apt autoremove -y | tee "$LOG_DIR/08-autoremove-trixie.log" || true
apt clean

# --- Проверки и информация ---
log "Версия после апгрейда:"
( . /etc/os-release; echo "NAME=$NAME VERSION=$VERSION (CODENAME=${VERSION_CODENAME:-unknown})" ) | tee "$LOG_DIR/09-os-release-after.log"
uname -a | tee -a "$LOG_DIR/09-os-release-after.log"

log "Апгрейд завершён. Перезагружаю систему через 5 секунд..."
sleep 5
reboot
