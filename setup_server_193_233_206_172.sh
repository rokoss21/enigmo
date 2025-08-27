#!/bin/bash

# 🚀 ENIGMO SERVER SETUP for VPS 193.233.206.172
# This script sets up the Enigmo messaging server on your production VPS

set -e

echo "🚀 Starting Enigmo server setup for IP 193.233.206.172..."
echo "📋 This script will:"
echo "   • Update the system"
echo "   • Install necessary software (nginx, dart, coturn)"
echo "   • Setup HTTPS with Let's Encrypt"
echo "   • Configure TURN server for voice calls"
echo "   • Deploy the Enigmo server"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script needs to run as root"
   echo "Usage: ssh root@193.233.206.172 'bash -s' < setup_server_193_233_206_172.sh"
   exit 1
fi

# Server configuration
SERVER_IP="193.233.206.172"
SERVER_PORT="8081"

# Get domain and email from user
read -p "Enter your domain name (or press Enter to use IP only): " DOMAIN
if [[ -z "$DOMAIN" ]]; then
    DOMAIN="$SERVER_IP"
    USE_SSL=false
    echo "📝 Will use IP address: $DOMAIN"
else
    USE_SSL=true
    echo "📝 Will use domain: $DOMAIN"
    read -p "Enter email for Let's Encrypt SSL certificate: " EMAIL
fi

echo ""
echo "🔧 Configuration:"
echo "   Server IP: $SERVER_IP"
echo "   Domain/IP: $DOMAIN"
echo "   Port: $SERVER_PORT"
echo "   SSL: $USE_SSL"
echo ""

# Update system
echo "🔄 Updating system packages..."
apt update && apt upgrade -y

# Install basic tools
echo "📦 Installing basic tools..."
apt install -y curl wget git unzip build-essential

# Install Dart SDK
echo "📦 Installing Dart SDK..."
if ! command -v dart &> /dev/null; then
    # Add Google's signing key
    wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/dart.gpg
    echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/dart.gpg] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main' | tee /etc/apt/sources.list.d/dart.list
    apt update
    apt install -y dart
    
    # Add dart to PATH
    echo 'export PATH="/usr/lib/dart/bin:$PATH"' >> ~/.bashrc
    export PATH="/usr/lib/dart/bin:$PATH"
else
    echo "✅ Dart SDK already installed"
fi

# Install nginx
echo "📦 Installing nginx..."
apt install -y nginx

# Install coturn for WebRTC TURN server
echo "📦 Installing coturn..."
apt install -y coturn

# Setup firewall
echo "🔥 Configuring firewall..."
ufw --force enable
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow $SERVER_PORT/tcp
ufw allow 3478/udp
ufw allow 5349/tcp

echo "✅ Firewall configured"

# Configure coturn
echo "🌐 Configuring TURN server (coturn)..."
cat > /etc/turnserver.conf << EOF
listening-port=3478
tls-listening-port=5349
listening-ip=0.0.0.0
relay-ip=$SERVER_IP
external-ip=$SERVER_IP
realm=$DOMAIN
server-name=$DOMAIN
lt-cred-mech
user=enigmo:enigmo123
log-file=/var/log/turnserver.log
simple-log
EOF

# Enable coturn service
systemctl enable coturn
systemctl start coturn

# Configure nginx
echo "🌐 Configuring nginx..."
if [[ "$USE_SSL" == true ]]; then
    # Install certbot for SSL
    apt install -y certbot python3-certbot-nginx
    
    # Create nginx config with SSL
    cat > /etc/nginx/sites-available/$DOMAIN << EOF
server {
    listen 80;
    server_name $DOMAIN;
    
    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    
    # SSL configuration will be added by certbot
    
    location / {
        proxy_pass http://localhost:$SERVER_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket timeouts
        proxy_connect_timeout 7d;
        proxy_send_timeout 7d;
        proxy_read_timeout 7d;
    }
    
    # Health check endpoint
    location /api/health {
        proxy_pass http://localhost:$SERVER_PORT;
        add_header Access-Control-Allow-Origin *;
    }
}
EOF

    # Enable site
    ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Test nginx config
    nginx -t
    systemctl reload nginx
    
    # Get SSL certificate
    echo "🔒 Obtaining SSL certificate..."
    certbot --nginx -d $DOMAIN --email $EMAIL --agree-tos --non-interactive --redirect
    
    # Setup auto-renewal
    (crontab -l ; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
    
else
    # HTTP-only configuration
    cat > /etc/nginx/sites-available/enigmo << EOF
server {
    listen 80;
    server_name $SERVER_IP;
    
    location / {
        proxy_pass http://localhost:$SERVER_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket timeouts
        proxy_connect_timeout 7d;
        proxy_send_timeout 7d;
        proxy_read_timeout 7d;
    }
}
EOF

    # Enable site
    ln -sf /etc/nginx/sites-available/enigmo /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Test nginx config
    nginx -t
    systemctl reload nginx
fi

# Create enigmo directory
echo "📁 Setting up Enigmo application directory..."
mkdir -p /opt/enigmo
cd /opt/enigmo

# Clone the repository
echo "📥 Downloading Enigmo source code..."
if [[ -d "enigmo" ]]; then
    echo "⚠️  Enigmo directory exists, updating..."
    cd enigmo
    git pull origin main
else
    git clone https://github.com/rokoss21/enigmo.git
    cd enigmo
fi

# Build server
echo "🔨 Building Enigmo server..."
cd enigmo_server
dart pub get
dart compile exe bin/anongram_server.dart -o bin/server

# Create systemd service
echo "🔧 Creating systemd service..."
cat > /etc/systemd/system/enigmo.service << EOF
[Unit]
Description=Enigmo Secure Messaging Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/enigmo/enigmo/enigmo_server
ExecStart=/opt/enigmo/enigmo/enigmo_server/bin/server --host=0.0.0.0 --port=$SERVER_PORT
Restart=always
RestartSec=10
KillSignal=SIGINT
TimeoutStopSec=30

# Security settings
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/opt/enigmo
PrivateTmp=yes

# Environment
Environment=DART_ENV=production

[Install]
WantedBy=multi-user.target
EOF

# Enable and start services
echo "🚀 Starting services..."
systemctl daemon-reload
systemctl enable enigmo
systemctl start enigmo

# Wait a moment for service to start
sleep 3

# Check service status
echo "📊 Checking service status..."
systemctl status enigmo --no-pager -l

echo ""
echo "🎉 ENIGMO SERVER INSTALLATION COMPLETE!"
echo ""
echo "📋 SERVER INFORMATION:"
if [[ "$USE_SSL" == true ]]; then
    echo "🌐 Server URL: https://$DOMAIN"
    echo "📊 Health Check: https://$DOMAIN/api/health"
    echo "📈 Statistics: https://$DOMAIN/api/stats"
    echo "🔌 WebSocket: wss://$DOMAIN/ws"
else
    echo "🌐 Server URL: http://$DOMAIN"
    echo "📊 Health Check: http://$DOMAIN/api/health"
    echo "📈 Statistics: http://$DOMAIN/api/stats"
    echo "🔌 WebSocket: ws://$DOMAIN:$SERVER_PORT/ws"
fi
echo "🔧 TURN Server (UDP): $DOMAIN:3478"
echo "🔧 TURN Server (TCP): $DOMAIN:5349"
echo "👤 TURN Username: enigmo"
echo "🔑 TURN Password: enigmo123"
echo ""
echo "📝 SERVICE COMMANDS:"
echo "   Status:  systemctl status enigmo"
echo "   Restart: systemctl restart enigmo"
echo "   Logs:    journalctl -u enigmo -f"
echo "   Stop:    systemctl stop enigmo"
echo ""
echo "🧪 TESTING:"
if [[ "$USE_SSL" == true ]]; then
    echo "   curl https://$DOMAIN/api/health"
else
    echo "   curl http://$DOMAIN/api/health"
fi
echo ""
echo "⚠️  IMPORTANT NEXT STEPS:"
echo "1. Update your Flutter app client configuration to point to this server"
echo "2. Rebuild your Flutter app with the new server settings"
echo "3. Test message sending and voice calls"
echo "4. Monitor logs with: journalctl -u enigmo -u nginx -u coturn -f"
echo ""
echo "🎊 Your Enigmo server is ready to use!"
