#!/bin/bash

# 🚀 ПРОДАКШН НАСТРОЙКА СЕРВЕРА ДЛЯ ЗВОНКОВ ENIGMO
# Запустите этот скрипт на вашем сервере с sudo правами

set -e

echo "🚀 Начинаем настройку продакшн сервера для звонков Enigmo..."

# Проверка на root права
if [[ $EUID -ne 0 ]]; then
   echo "❌ Этот скрипт нужно запускать с sudo правами"
   echo "Используйте: sudo bash setup_production_server.sh"
   exit 1
fi

# Переменные для настройки
read -p "Введите ваш домен (например, yourdomain.com): " DOMAIN
read -p "Введите email для Let's Encrypt: " EMAIL

echo "📋 Настройка для домена: $DOMAIN"
echo "📧 Email для SSL: $EMAIL"

# Обновление системы
echo "🔄 Обновление системы..."
apt update && apt upgrade -y

# Установка необходимого ПО
echo "📦 Установка необходимого ПО..."
apt install -y nginx certbot python3-certbot-nginx coturn ufw curl wget git

# Настройка firewall
echo "🔥 Настройка firewall..."
ufw --force enable
ufw allow ssh
ufw allow 80
ufw allow 443
ufw allow 8081
ufw allow 3478
ufw allow 5349

# Настройка TURN сервера
echo "🌐 Настройка TURN сервера..."
cat > /etc/turnserver.conf << EOF
listening-port=3478
tls-listening-port=5349
listening-ip=0.0.0.0
relay-ip=$(curl -s ifconfig.me)
external-ip=$(curl -s ifconfig.me)
realm=$DOMAIN
server-name=$DOMAIN
lt-cred-mech
user=enigmo:enigmo123
cert=/etc/letsencrypt/live/$DOMAIN/fullchain.pem
pkey=/etc/letsencrypt/live/$DOMAIN/privkey.pem
log-file=/var/log/turnserver.log
simple-log
EOF

# Создание сервиса для TURN
cat > /etc/systemd/system/coturn.service << EOF
[Unit]
Description=TURN Server
After=network.target

[Service]
Type=simple
User=turnserver
Group=turnserver
ExecStart=/usr/bin/turnserver -c /etc/turnserver.conf
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Настройка nginx
echo "🌐 Настройка nginx..."
cat > /etc/nginx/sites-available/$DOMAIN << EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:8081;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket таймауты
        proxy_connect_timeout 7d;
        proxy_send_timeout 7d;
        proxy_read_timeout 7d;
    }
}
EOF

# Включение сайта
ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# Получение SSL сертификата
echo "🔒 Получение SSL сертификата..."
certbot --nginx -d $DOMAIN --email $EMAIL --agree-tos --non-interactive

# Настройка автопродления SSL
echo "⏰ Настройка автопродления SSL..."
(crontab -l ; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -

# Запуск TURN сервера
echo "🚀 Запуск TURN сервера..."
systemctl enable coturn
systemctl start coturn

# Создание директории для приложения
echo "📁 Создание директории для приложения..."
mkdir -p /opt/enigmo
cd /opt/enigmo

# Инструкции для деплоя приложения
cat > /opt/enigmo/deploy_instructions.txt << 'EOF'
📋 ИНСТРУКЦИИ ПО ДЕПЛОЮ ПРИЛОЖЕНИЯ

1. Скопируйте ваше приложение на сервер:
   scp -r /path/to/enigmo_server user@your-server:/opt/enigmo/

2. Установите Dart SDK:
   wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add -
   echo 'deb [arch=amd64] http://storage.googleapis.com/download.dartlang.org/linux/debian stable main' | tee /etc/apt/sources.list.d/dart.list
   apt update && apt install -y dart

3. Соберите приложение:
   cd /opt/enigmo/enigmo_server
   dart pub get
   dart compile exe bin/anongram_server.dart -o bin/server

4. Создайте сервис для приложения:
   sudo nano /etc/systemd/system/enigmo.service

   [Unit]
   Description=Enigmo Server
   After=network.target

   [Service]
   Type=simple
   User=ubuntu
   WorkingDirectory=/opt/enigmo/enigmo_server
   ExecStart=/opt/enigmo/enigmo_server/bin/server --host=0.0.0.0 --port=8081
   Restart=always
   RestartSec=5

   [Install]
   WantedBy=multi-user.target

5. Запустите сервис:
   sudo systemctl enable enigmo
   sudo systemctl start enigmo

6. Проверьте статус:
   sudo systemctl status enigmo
   curl http://localhost:8081/api/health

🚨 ВАЖНО: Обновите клиентское приложение с TURN серверами!

В файле enigmo/enigmo_app/lib/services/audio_call_service.dart
замените комментарии на реальные TURN серверы:

'iceServers': [
  {'urls': 'stun:stun.l.google.com:19302'},
  {'urls': 'stun:stun1.l.google.com:19302'},
  {'urls': 'stun:stun2.l.google.com:19302'},
  {
    'urls': 'turn:$DOMAIN:3478',
    'username': 'enigmo',
    'credential': 'enigmo123'
  },
  {
    'urls': 'turn:$DOMAIN:5349',
    'username': 'enigmo',
    'credential': 'enigmo123'
  }
],
EOF

echo ""
echo "🎉 СЕРВЕР НАСТРОЕН!"
echo ""
echo "📋 СЛЕДУЮЩИЕ ШАГИ:"
echo "1. Скопируйте ваше приложение на сервер в /opt/enigmo/"
echo "2. Следуйте инструкциям в /opt/enigmo/deploy_instructions.txt"
echo "3. Обновите клиентское приложение с TURN серверами"
echo "4. Протестируйте звонки"
echo ""
echo "🌐 Ваш сервер доступен по адресу: https://$DOMAIN"
echo "🔧 TURN сервер работает на портах: 3478, 5349"
echo "📊 Мониторинг: https://$DOMAIN/api/health"
echo ""
echo "⚠️  НЕ ЗАБУДЬТЕ обновить клиентское приложение с вашими TURN серверами!"