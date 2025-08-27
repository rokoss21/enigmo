#!/bin/bash

# 🧪 ТЕСТИРОВАНИЕ ПРОДАКШН СЕРВЕРА ДЛЯ ЗВОНКОВ ENIGMO
# Запустите этот скрипт после настройки сервера

echo "🧪 Начинаем тестирование продакшн сервера..."

# Проверка аргументов
if [ $# -eq 0 ]; then
    echo "❌ Укажите домен для тестирования"
    echo "Использование: bash test_production_server.sh yourdomain.com"
    exit 1
fi

DOMAIN=$1
echo "🌐 Тестирование домена: $DOMAIN"

# Функция для проверки с цветовым выводом
check_service() {
    local url=$1
    local service_name=$2

    echo -n "🔍 Проверка $service_name ($url)... "

    if curl -s --max-time 10 "$url" > /dev/null; then
        echo "✅ OK"
        return 0
    else
        echo "❌ FAILED"
        return 1
    fi
}

# Функция для проверки с выводом ответа
check_service_verbose() {
    local url=$1
    local service_name=$2

    echo "🔍 Проверка $service_name ($url):"
    echo "----------------------------------------"

    response=$(curl -s --max-time 10 "$url" || echo "ERROR: Connection failed")

    if [[ $response == *"ERROR"* ]]; then
        echo "❌ FAILED: $response"
        return 1
    else
        echo "$response" | head -20
        echo "----------------------------------------"
        echo "✅ OK"
        return 0
    fi
}

echo ""
echo "📋 ПРОВЕРКА ОСНОВНЫХ СЕРВИСОВ:"
echo "================================="

# Проверка HTTPS
check_service "https://$DOMAIN/api/health" "HTTPS Health Check"

# Проверка WebSocket (базовая)
check_service "https://$DOMAIN/ws" "WebSocket Endpoint"

# Проверка TURN сервера (UDP)
echo -n "🔍 Проверка TURN сервера (UDP:3478)... "
if nc -z -u $DOMAIN 3478 2>/dev/null; then
    echo "✅ OK"
else
    echo "❌ FAILED (UDP port closed)"
fi

# Проверка TURN сервера (TCP)
echo -n "🔍 Проверка TURN сервера (TCP:5349)... "
if nc -z $DOMAIN 5349 2>/dev/null; then
    echo "✅ OK"
else
    echo "❌ FAILED (TCP port closed)"
fi

echo ""
echo "📋 ДЕТАЛЬНАЯ ПРОВЕРКА:"
echo "======================="

# Детальная проверка здоровья
check_service_verbose "https://$DOMAIN/api/health" "Server Health"

# Детальная проверка статистики
check_service_verbose "https://$DOMAIN/api/stats" "Server Statistics"

echo ""
echo "🔧 ДОПОЛНИТЕЛЬНЫЕ ПРОВЕРКИ:"
echo "============================"

# Проверка SSL сертификата
echo "🔍 Проверка SSL сертификата:"
echo "----------------------------------------"
openssl s_client -connect $DOMAIN:443 -servername $DOMAIN < /dev/null 2>/dev/null | openssl x509 -noout -dates -subject -issuer 2>/dev/null || echo "❌ SSL certificate check failed"

echo ""
echo "🌐 ДОСТУПНОСТЬ СЕТИ:"
echo "==================="

# Проверка доступности портов
echo "🔍 Сканирование открытых портов:"
echo "----------------------------------------"
nmap -p 80,443,8081,3478,5349 $DOMAIN 2>/dev/null || echo "❌ nmap не установлен, пропускаем сканирование"

echo ""
echo "📋 РЕЗУЛЬТАТЫ ТЕСТИРОВАНИЯ:"
echo "=========================="

# Проверка всех компонентов
all_good=true

# Проверка HTTPS
if ! curl -s --max-time 5 "https://$DOMAIN/api/health" > /dev/null; then
    echo "❌ HTTPS не работает"
    all_good=false
else
    echo "✅ HTTPS работает"
fi

# Проверка TURN
if ! nc -z -u $DOMAIN 3478 2>/dev/null; then
    echo "❌ TURN UDP (3478) не доступен"
    all_good=false
else
    echo "✅ TURN UDP (3478) доступен"
fi

if ! nc -z $DOMAIN 5349 2>/dev/null; then
    echo "❌ TURN TCP (5349) не доступен"
    all_good=false
else
    echo "✅ TURN TCP (5349) доступен"
fi

echo ""
if $all_good; then
    echo "🎉 ВСЕ СЕРВИСЫ РАБОТАЮТ КОРРЕКТНО!"
    echo ""
    echo "🚀 ГОТОВО К ТЕСТИРОВАНИЮ ЗВОНКОВ:"
    echo "1. Откройте https://$DOMAIN в браузере"
    echo "2. Попробуйте позвонить между двумя вкладками"
    echo "3. Проверьте логи браузера (F12) на наличие ошибок"
    echo ""
    echo "⚠️  НЕ ЗАБУДЬТЕ: Обновите клиентское приложение с TURN серверами!"
    echo "   В файле audio_call_service.dart замените комментарии на:"
    echo "   'urls': 'turn:$DOMAIN:3478'"
    echo "   'username': 'enigmo'"
    echo "   'credential': 'enigmo123'"
else
    echo "⚠️  НЕКОТОРЫЕ СЕРВИСЫ НЕ РАБОТАЮТ!"
    echo ""
    echo "🔧 ПРОВЕРЬТЕ:"
    echo "1. Статус nginx: sudo systemctl status nginx"
    echo "2. Статус coturn: sudo systemctl status coturn"
    echo "3. Статус приложения: sudo systemctl status enigmo"
    echo "4. Логи: sudo journalctl -u nginx -u coturn -u enigmo --no-pager -n 50"
fi

echo ""
echo "📊 ДОПОЛНИТЕЛЬНАЯ ИНФОРМАЦИЯ:"
echo "=============================="
echo "🌐 Сервер: https://$DOMAIN"
echo "🔧 TURN UDP: $DOMAIN:3478"
echo "🔧 TURN TCP: $DOMAIN:5349"
echo "📈 Мониторинг: https://$DOMAIN/api/health"
echo "📋 Статистика: https://$DOMAIN/api/stats"