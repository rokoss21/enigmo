# Руководство по развертыванию сервера Enigmo

Это руководство поможет вам развернуть серверную часть Enigmo на чистом сервере с **Ubuntu 22.04**.

## Шаг 1: Подключитесь к вашему серверу

Подключитесь к вашему серверу по SSH. Замените `193.233.206.172` на IP-адрес вашего сервера.

```bash
ssh root@193.233.206.172
```

## Шаг 2: Выполните скрипт автоматической установки

Этот скрипт автоматически выполнит все необходимые действия: обновит систему, установит Git и Dart SDK, склонирует репозиторий, соберет проект и настроит фоновый сервис.

Скопируйте и вставьте всю команду ниже в терминал вашего сервера и нажмите Enter.

```bash
# Установка зависимостей
echo ">>> Установка зависимостей (git, curl, unzip)..."
apt-get update && apt-get install -y git curl unzip

# Установка Dart SDK
echo ">>> Установка Dart SDK..."
curl -fL "https://storage.googleapis.com/dart-archive/channels/stable/release/latest/sdk/dartsdk-linux-x64-release.zip" -o dart-sdk.zip
unzip dart-sdk.zip -d /usr/lib/
rm dart-sdk.zip
export PATH="$PATH:/usr/lib/dart-sdk/bin"
echo 'export PATH="$PATH:/usr/lib/dart-sdk/bin"' >> ~/.bashrc

# Проверка установки Dart
dart --version

# Клонирование репозитория (ветка testvoice)
echo ">>> Клонирование репозитория..."
git clone --branch testvoice https://github.com/rokoss21/enigmo.git /opt/enigmo

# Сборка сервера
echo ">>> Сборка исполняемого файла сервера..."
cd /opt/enigmo/enigmo_server
dart pub get
dart compile exe bin/anongram_server.dart -o /usr/local/bin/enigmo_server

# Проверка сборки
ls -l /usr/local/bin/enigmo_server

# Создание сервиса systemd для автозапуска
echo ">>> Создание сервиса systemd..."
cat > /etc/systemd/system/enigmo.service << EOL
[Unit]
Description=Enigmo Secure Messaging Server
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/enigmo_server --host 0.0.0.0 --port 8081
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOL

# Перезагрузка systemd, включение и запуск сервиса
echo ">>> Запуск сервера Enigmo..."
systemctl daemon-reload
systemctl enable enigmo.service
systemctl start enigmo.service

echo ">>> Установка завершена!"
```

## Шаг 3: Проверьте статус сервера

После выполнения скрипта проверьте, что сервер успешно запустился.

```bash
systemctl status enigmo.service
```

Вы должны увидеть `active (running)` зеленого цвета.

Чтобы посмотреть логи сервера в реальном времени, используйте команду:

```bash
journalctl -u enigmo.service -f
```

Нажмите `Ctrl+C`, чтобы выйти из просмотра логов.

## Управление сервером

-   **Остановить сервер:** `systemctl stop enigmo.service`
-   **Запустить сервер:** `systemctl start enigmo.service`
-   **Перезапустить сервер:** `systemctl restart enigmo.service`

---

### **ВАЖНОЕ НАПОМИНАНИЕ О БЕЗОПАСНОСТИ**

**Немедленно отзовите токен GitHub, который вы предоставили.** Он больше не нужен для развертывания.
