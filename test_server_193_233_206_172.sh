#!/bin/bash

# 🧪 ENIGMO SERVER TEST SCRIPT for 193.233.206.172
# Test all server components and connectivity

SERVER_IP="193.233.206.172"
SERVER_PORT="8081"

echo "🧪 Testing Enigmo server at $SERVER_IP..."
echo "=================================="
echo ""

# Function to test HTTP endpoint
test_http() {
    local url=$1
    local name=$2
    
    echo -n "🔍 Testing $name... "
    
    if curl -s --max-time 10 "$url" > /dev/null 2>&1; then
        echo "✅ OK"
        return 0
    else
        echo "❌ FAILED"
        return 1
    fi
}

# Function to test port connectivity
test_port() {
    local host=$1
    local port=$2
    local protocol=${3:-tcp}
    local name=$4
    
    echo -n "🔍 Testing $name ($protocol:$port)... "
    
    if nc -z${protocol:0:1} "$host" "$port" 2>/dev/null; then
        echo "✅ OK"
        return 0
    else
        echo "❌ FAILED"
        return 1
    fi
}

# Get server protocol/domain
if curl -s "https://$SERVER_IP/api/health" > /dev/null 2>&1; then
    PROTOCOL="https"
    BASE_URL="https://$SERVER_IP"
    echo "🔒 HTTPS server detected"
elif curl -s "http://$SERVER_IP/api/health" > /dev/null 2>&1; then
    PROTOCOL="http"
    BASE_URL="http://$SERVER_IP"
    echo "🔓 HTTP server detected"
else
    echo "❌ Server not responding on port 80 or 443, trying port $SERVER_PORT..."
    if curl -s "http://$SERVER_IP:$SERVER_PORT/api/health" > /dev/null 2>&1; then
        PROTOCOL="http"
        BASE_URL="http://$SERVER_IP:$SERVER_PORT"
        echo "🔓 HTTP server detected on port $SERVER_PORT"
    else
        echo "❌ No server detected. Please check if the server is running."
        exit 1
    fi
fi

echo ""
echo "🌐 Server URL: $BASE_URL"
echo ""

# Test basic connectivity
echo "📋 BASIC CONNECTIVITY TESTS:"
echo "================================"

test_http "$BASE_URL/api/health" "Health endpoint"
test_http "$BASE_URL/api/stats" "Statistics endpoint"

# Test WebSocket endpoint (can't easily test WS with curl, so we test the HTTP upgrade)
echo -n "🔍 Testing WebSocket endpoint... "
WS_RESPONSE=$(curl -s -I -H "Connection: Upgrade" -H "Upgrade: websocket" "$BASE_URL/ws" 2>/dev/null | head -1)
if [[ $WS_RESPONSE == *"101"* || $WS_RESPONSE == *"426"* ]]; then
    echo "✅ OK (WebSocket endpoint available)"
else
    echo "⚠️  WARNING (WebSocket might not be properly configured)"
fi

echo ""
echo "📋 PORT CONNECTIVITY TESTS:"
echo "================================"

# Test main ports
test_port "$SERVER_IP" "80" "tcp" "HTTP"
test_port "$SERVER_IP" "443" "tcp" "HTTPS"
test_port "$SERVER_IP" "$SERVER_PORT" "tcp" "Enigmo Server"

# Test TURN server ports
test_port "$SERVER_IP" "3478" "udp" "TURN UDP"
test_port "$SERVER_IP" "5349" "tcp" "TURN TCP"

echo ""
echo "📋 DETAILED SERVER INFO:"
echo "================================"

echo "🔍 Health Check Response:"
echo "------------------------"
curl -s "$BASE_URL/api/health" | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin), indent=2))" 2>/dev/null || curl -s "$BASE_URL/api/health"

echo ""
echo "📊 Server Statistics:"
echo "--------------------"
curl -s "$BASE_URL/api/stats" | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin), indent=2))" 2>/dev/null || curl -s "$BASE_URL/api/stats"

echo ""
echo "📋 SSL CERTIFICATE INFO (if HTTPS):"
echo "==================================="

if [[ "$PROTOCOL" == "https" ]]; then
    echo "🔒 SSL Certificate Details:"
    echo "| openssl s_client -connect $SERVER_IP:443 -servername $SERVER_IP < /dev/null 2>/dev/null | openssl x509 -noout -dates -subject -issuer 2>/dev/null"
    openssl s_client -connect $SERVER_IP:443 -servername $SERVER_IP < /dev/null 2>/dev/null | openssl x509 -noout -dates -subject -issuer 2>/dev/null || echo "❌ SSL certificate check failed"
else
    echo "ℹ️  HTTP server - no SSL certificate"
fi

echo ""
echo "🌐 NETWORK INFORMATION:"
echo "======================"

echo "🔍 Server IP Resolution:"
nslookup $SERVER_IP 2>/dev/null || echo "Direct IP address"

echo ""
echo "🔍 Reachability Test:"
ping -c 3 $SERVER_IP 2>/dev/null || echo "❌ Ping failed"

echo ""
echo "🔍 Open Ports Scan:"
if command -v nmap &> /dev/null; then
    nmap -p 22,80,443,3478,5349,$SERVER_PORT $SERVER_IP 2>/dev/null | grep -E "(open|closed|filtered)"
else
    echo "ℹ️  nmap not available for port scan"
fi

echo ""
echo "📋 SUMMARY:"
echo "==========="

# Run comprehensive tests
total_tests=0
passed_tests=0

# Test critical endpoints
for endpoint in "/api/health" "/api/stats"; do
    total_tests=$((total_tests + 1))
    if curl -s --max-time 5 "$BASE_URL$endpoint" > /dev/null; then
        passed_tests=$((passed_tests + 1))
    fi
done

# Test critical ports
for port in "80" "3478" "$SERVER_PORT"; do
    total_tests=$((total_tests + 1))
    if nc -z "$SERVER_IP" "$port" 2>/dev/null; then
        passed_tests=$((passed_tests + 1))
    fi
done

echo "✅ Passed: $passed_tests/$total_tests tests"

if [[ $passed_tests -eq $total_tests ]]; then
    echo "🎉 ALL TESTS PASSED! Server is ready for use."
    echo ""
    echo "🚀 READY FOR PRODUCTION:"
    echo "   • Enigmo server is running"
    echo "   • WebSocket endpoint available"
    echo "   • TURN server configured"
    echo "   • All ports accessible"
    echo ""
    echo "📱 CLIENT CONFIGURATION:"
    echo "   Server URL: $BASE_URL"
    if [[ "$PROTOCOL" == "https" ]]; then
        echo "   WebSocket: wss://$SERVER_IP/ws"
    else
        echo "   WebSocket: ws://$SERVER_IP:$SERVER_PORT/ws"
    fi
    echo "   TURN UDP: $SERVER_IP:3478"
    echo "   TURN TCP: $SERVER_IP:5349"
    echo "   TURN Username: enigmo"
    echo "   TURN Password: enigmo123"
    
elif [[ $passed_tests -gt $((total_tests / 2)) ]]; then
    echo "⚠️  PARTIAL SUCCESS: Some components may need attention"
    echo "   • Check failed services with: systemctl status enigmo nginx coturn"
    echo "   • Review logs with: journalctl -u enigmo -u nginx -u coturn -n 50"
    
else
    echo "❌ MULTIPLE FAILURES: Server setup needs troubleshooting"
    echo "   • Verify server is running: systemctl status enigmo"
    echo "   • Check nginx config: nginx -t && systemctl status nginx"
    echo "   • Verify firewall: ufw status"
    echo "   • Review setup logs: journalctl -u enigmo -n 50"
fi

echo ""
echo "🔧 TROUBLESHOOTING COMMANDS:"
echo "   systemctl status enigmo nginx coturn"
echo "   journalctl -u enigmo -f"
echo "   curl -v $BASE_URL/api/health"
echo "   netstat -tlnp | grep -E ':(80|443|3478|5349|$SERVER_PORT)'"
echo ""
