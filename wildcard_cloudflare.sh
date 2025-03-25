#!/bin/bash

# ==== Настройки ====
LOG_FILE="/var/log/certbot_renew.log"
ERROR_LOG="/var/log/certbot_errors.log"
CLOUDFLARE_CREDENTIALS="/etc/letsencrypt/cloudflare/cloudflare.ini"
ACME_SERVER="https://acme-v02.api.letsencrypt.org/directory"
WAIT_TIME=10  # Время ожидания перед перезапуском Nginx
MAX_RETRIES=3 # Количество попыток обновления SSL

# ==== Настройки Telegram ====
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""  # ID супергруппы
TELEGRAM_TOPIC_ID=""           # ID топика
TELEGRAM_API_URL="https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage"

# Получаем внутренний IP-адрес сервера
INTERNAL_IP=$(ip a | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n 1)

# Функция для логирования
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Функция отправки Telegram-оповещений в топик
send_telegram_alert() {
    local message="$1"
    response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$TELEGRAM_API_URL" \
        -d "chat_id=$TELEGRAM_CHAT_ID" \
        -d "message_thread_id=$TELEGRAM_TOPIC_ID" \
        -d "text=$message")
    
    if [ "$response" -ne 200 ]; then
        log "⚠️ Ошибка отправки сообщения в Telegram (код ответа: $response)"
    fi
}

# Функция для проверки команд
check_command() {
    command -v "$1" >/dev/null 2>&1 || { 
        ERROR_MSG="❌ Ошибка: $1 не установлен на сервере $INTERNAL_IP!"
        log "$ERROR_MSG"
        send_telegram_alert "$ERROR_MSG"
        exit 1
    }
}

# Проверка наличия необходимых команд
check_command certbot
check_command systemctl
check_command curl
check_command nginx

# Проверка, переданы ли домены
if [ "$#" -lt 1 ]; then
    ERROR_MSG="❌ Ошибка SSL-обновления: не указан домен! Сервер: $INTERNAL_IP"
    log "$ERROR_MSG"
    send_telegram_alert "$ERROR_MSG"
    exit 1
fi

# Перебираем переданные домены
for DOMAIN in "$@"; do
    log "🚀 Начало обновления SSL для $DOMAIN на сервере $INTERNAL_IP"

    for attempt in $(seq 1 $MAX_RETRIES); do
        log "🔄 Попытка $attempt из $MAX_RETRIES..."

        # Запуск обновления сертификата
        certbot certonly --dns-cloudflare \
            --dns-cloudflare-credentials "$CLOUDFLARE_CREDENTIALS" \
            -d "$DOMAIN" -d "*.$DOMAIN" \
            --preferred-challenges dns-01 \
            --agree-tos \
            --non-interactive \
            --server "$ACME_SERVER" \
            --force-renewal 2>>"$ERROR_LOG" | tee -a "$LOG_FILE"

        # Сохранение кода завершения certbot
        EXIT_CODE=${PIPESTATUS[0]}

        if [ $EXIT_CODE -eq 0 ]; then
            log "✅ Сертификат успешно обновлен для $DOMAIN"
            SUCCESS_MSG="✅ SSL-сертификат обновлен для $DOMAIN на сервере $INTERNAL_IP!"
            send_telegram_alert "$SUCCESS_MSG"
            break
        else
            log "⚠️ Ошибка обновления сертификата для $DOMAIN (код: $EXIT_CODE)"
            log "🔁 Повтор через 5 секунд..."
            sleep 5
        fi
    done

    if [ $EXIT_CODE -ne 0 ]; then
        ERROR_MSG="❌ Критическая ошибка обновления SSL для $DOMAIN на сервере $INTERNAL_IP! Проверьте $ERROR_LOG"
        log "$ERROR_MSG"
        send_telegram_alert "$ERROR_MSG"
        exit 1
    fi

    # Ожидание перед перезапуском Nginx
    log "⏳ Ожидание $WAIT_TIME секунд перед перезагрузкой Nginx..."
    sleep $WAIT_TIME

    # Проверка конфигурации перед перезапуском Nginx
    if nginx -t 2>/dev/null; then
        systemctl reload nginx
        log "🔄 Nginx успешно перезагружен"
        send_telegram_alert "🔄 Nginx перезагружен после обновления SSL на сервере $INTERNAL_IP"
    else
        ERROR_MSG="🚨 Ошибка: Конфигурация Nginx неверна на сервере $INTERNAL_IP!"
        log "$ERROR_MSG"
        send_telegram_alert "$ERROR_MSG"
        exit 2
    fi
done

FINAL_MSG="✅ Все домены успешно обновлены на сервере $INTERNAL_IP!"
log "$FINAL_MSG"
send_telegram_alert "$FINAL_MSG"
exit 0
