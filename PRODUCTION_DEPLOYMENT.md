# 🚀 Продакшн деплой для звонков Enigmo

## ⚠️ **КРИТИЧЕСКИЕ ТРЕБОВАНИЯ ДЛЯ ПРОДАКШНА**

### 1. **HTTPS ОБЯЗАТЕЛЕН**
```bash
# Получите SSL сертификат (Let's Encrypt)
certbot certonly --webroot -w /var/www/html -d yourdomain.com

# Или используйте reverse proxy (nginx)
server {
    listen 443 ssl;
    server_name yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;

    location / {
        proxy_pass http://localhost:8081;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### 2. **TURN СЕРВЕР ОБЯЗАТЕЛЕН**
```bash
# Установите coturn
sudo apt install coturn

# Конфигурация /etc/turnserver.conf
listening-port=3478
tls-listening-port=5349
listening-ip=0.0.0.0
relay-ip=YOUR_SERVER_IP
external-ip=YOUR_SERVER_IP
realm=yourdomain.com
server-name=yourdomain.com
lt-cred-mech
user=test:test123
cert=/etc/letsencrypt/live/yourdomain.com/fullchain.pem
pkey=/etc/letsencrypt/live/yourdomain.com/privkey.pem
```

### 3. **ДОБАВИТЬ TURN В КЛИЕНТ**
```dart
// В AudioCallService.dart добавить TURN сервер
final configuration = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
    {'urls': 'stun:stun2.l.google.com:19302'},
    {
      'urls': 'turn:yourdomain.com:3478',
      'username': 'test',
      'credential': 'test123'
    },
    {
      'urls': 'turn:yourdomain.com:5349',
      'username': 'test',
      'credential': 'test123'
    }
  ],
  // ... остальные настройки
};
```

### 4. **КОНФИГУРАЦИЯ СЕРВЕРА**
```dart
// В AnogramServer.dart изменить порт по умолчанию
Future<void> initialize({
  String host = '0.0.0.0',  // Слушать на всех интерфейсах
  int port = 8081,
}) async {
  // ... остальной код
}
```

### 5. **FIREWALL НАСТРОЙКИ**
```bash
# Открыть порты
sudo ufw allow 80
sudo ufw allow 443
sudo ufw allow 8081
sudo ufw allow 3478
sudo ufw allow 5349
```

## 🧪 **ТЕСТИРОВАНИЕ ПРОДАКШНА**

### **Тест 1: Базовое соединение**
```bash
# Проверить HTTPS
curl -I https://yourdomain.com/api/health

# Проверить WebSocket
curl -I https://yourdomain.com/ws
```

### **Тест 2: WebRTC соединение**
```bash
# Открыть два браузера на https://yourdomain.com
# Попробовать позвонить между ними
# Проверить логи браузера (F12)
```

### **Тест 3: TURN сервер**
```bash
# Проверить TURN
turnutils_uclient -t -u test -w test123 yourdomain.com
```

## 📋 **ЧЕКЛИСТ ДЕПЛОЯ**

- [ ] HTTPS сертификат установлен
- [ ] TURN сервер настроен и работает
- [ ] Firewall открыт для нужных портов
- [ ] Сервер слушает на 0.0.0.0:8081
- [ ] Клиент обновлен с TURN конфигурацией
- [ ] Протестировано соединение между разными сетями

## 🎯 **ОЖИДАЕМЫЕ РЕЗУЛЬТАТЫ**

✅ **Работает:**
- Звонки между пользователями в одной сети
- Звонки через NAT/Firewall
- Звонки между мобильными и веб клиентами

⚠️ **Ограничения:**
- Требуется HTTPS
- Нужен TURN для сложных сетей
- Дополнительная нагрузка на сервер

## 🚨 **БЕЗ HTTPS/TURN НЕ БУДЕТ РАБОТАТЬ В ПРОДАКШНЕ!**