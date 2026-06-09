#!/bin/bash
set -e

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   echo "Ошибка: запустите скрипт от имени root (sudo ./dns.sh)"
   exit 1
fi

CONFIG_FILE="/etc/systemd/resolved.conf"
BACKUP_FILE="${CONFIG_FILE}.bak"

# Целевые значения
TARGET_DNS="DNS=1.1.1.1 1.0.0.1"
TARGET_FALLBACK="FallbackDNS=8.8.8.8 8.8.4.4"
TARGET_DOT="DNSOverTLS=yes"
TARGET_DNSSEC="DNSSEC=yes"
TARGET_CACHE="Cache=yes"

# Функция проверки и замены
check_and_set() {
    local key=$1
    local target_value=$2
    local current_value
    current_value=$(grep -E "^${key}=" "$CONFIG_FILE" | tail -n 1)

    if [[ "$current_value" == "$target_value" ]]; then
        return 0
    else
        local display_current="${current_value:-отсутствует или закомментирован}"
        echo "⚠️ Параметр '$key' не совпадает (текущий: '$display_current'). Заменяем на '$target_value'."
        
        if grep -qE "^#?${key}=" "$CONFIG_FILE"; then
            sed -i "s|^#*\(${key}\)=.*|\1=${target_value#*=}|" "$CONFIG_FILE"
        else
            echo "$target_value" >> "$CONFIG_FILE"
        fi
        return 1
    fi
}

echo "🔍 Проверка настроек в $CONFIG_FILE..."

# Резервная копия
if [[ ! -f "$BACKUP_FILE" ]]; then
    cp "$CONFIG_FILE" "$BACKUP_FILE"
fi

MISMATCH_COUNT=0

# Исправление: используем арифметическое присваивание вместо ((...))
# чтобы избежать ложного кода возврата при инкременте с 0 до 1
check_and_set "DNS" "$TARGET_DNS" || MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
check_and_set "FallbackDNS" "$TARGET_FALLBACK" || MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
check_and_set "DNSOverTLS" "$TARGET_DOT" || MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
check_and_set "DNSSEC" "$TARGET_DNSSEC" || MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
check_and_set "Cache" "$TARGET_CACHE" || MISMATCH_COUNT=$((MISMATCH_COUNT + 1))

echo "---------------------------------------------------"

if [[ $MISMATCH_COUNT -eq 0 ]]; then
    echo "✅ Изменений не внесено, настройки соответствуют указанным."
else
    echo "💾 Применяем изменения и перезапускаем службу..."
    systemctl restart systemd-resolved
    echo "✅ Готово. Внесено изменений: $MISMATCH_COUNT. Проверка статуса:"
    resolvectl status | grep -E 'DNSOverTLS|Current DNS Server'
fi

