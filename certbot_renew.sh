#!/bin/bash

# Добавляем PATH
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Telegram bot settings
BOT_TOKEN=""
CHAT_ID=""
LOG_FILE="/var/log/certbot_renew.log"

# Функция для отправки сообщения в Telegram
send_telegram_message() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d text="${message}"
}

# Логирование
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S'): ${message}" >> ${LOG_FILE}
}

# Проверка доступности интернета
check_internet() {
    if ! ping -c 1 google.com &> /dev/null; then
        log_message "No internet connection!"
        send_telegram_message "Certbot renewal failed: No internet connection!"
        exit 1
    fi
}

# Основная логика
main() {
    log_message "Starting certbot renewal process..."

    # Проверка доступности интернета
    check_internet

    # Выполнение certbot renew
    if certbot renew --quiet; then
        log_message "Certbot renewal succeeded!"
        send_telegram_message "Certbot renewal succeeded!"

        # Перезагрузка Nginx через 5 секунд
        log_message "Waiting 5 seconds before checking Nginx configuration..."
        sleep 5

        # Проверка конфигурации Nginx
        if nginx -t; then
            log_message "Nginx configuration is valid. Reloading Nginx..."
            if sudo systemctl reload nginx; then
                log_message "Nginx reloaded successfully!"
                send_telegram_message "Nginx reloaded successfully!"
            else
                log_message "Failed to reload Nginx!"
                send_telegram_message "Certbot renewal succeeded, but failed to reload Nginx!"
                exit 1
            fi
        else
            log_message "Nginx configuration is invalid!"
            send_telegram_message "Certbot renewal succeeded, but Nginx configuration is invalid!"
            exit 1
        fi
    else
        ERROR_MESSAGE=$(certbot renew 2>&1)
        log_message "Certbot renewal failed! Error: ${ERROR_MESSAGE}"
        send_telegram_message "Certbot renewal failed! Error: ${ERROR_MESSAGE}"
        exit 1
    fi
}

# Запуск основной логики
main
