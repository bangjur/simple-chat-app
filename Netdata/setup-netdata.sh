#!/bin/bash

# Netdata dengan Nginx Authentication Setup
# Server IP: 103.185.xxx.xxx
# Port: 19999 dengan password protection

echo "=== Setting up Netdata with Nginx Authentication ==="

# 1. Buat direktori kerja
mkdir -p netdata-secure
cd netdata-secure

# 2. Generate password file dengan nama yang unique
echo "Generating password file..."
sudo htpasswd -cb /etc/nginx/.htpasswd-netdata admin netdatanihbosku
echo "✓ Password file created (admin:netdatanihbosku)"

# 3. Buat netdata.conf untuk /etc/nginx/conf.d/
cat > netdata.conf << 'EOF'
# Netdata monitoring configuration
# This will be included in main nginx.conf

upstream netdata {
    server 127.0.0.1:19998;  # netdata container port
    keepalive 64;
}

server {
    listen 19999;
    server_name 103.185.xxx.xxx;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    
    location / {
        auth_basic "Netdata Monitoring Access";
        auth_basic_user_file /etc/nginx/.htpasswd-netdata;
        
        proxy_pass http://netdata;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support untuk real-time updates
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeout settings
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # Health check endpoint (tanpa auth)
    location /api/v1/info {
        auth_basic off;
        proxy_pass http://netdata;
        proxy_set_header Host $host;
    }
}
EOF

echo "✓ Netdata nginx config created"

# 4. Buat docker-compose.yml (simplified - gak perlu nginx container)
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  netdata:
    image: netdata/netdata
    container_name: netdata
    hostname: netdata-server-103.185.xxx.xxx
    ports:
      - "19998:19999"  # expose ke host sebagai port 19998
    restart: unless-stopped
    cap_add:
      - SYS_PTRACE
    security_opt:
      - apparmor:unconfined
    volumes:
      - netdataconfig:/etc/netdata
      - netdatalib:/var/lib/netdata
      - netdatacache:/var/cache/netdata
      - /etc/passwd:/host/etc/passwd:ro
      - /etc/group:/host/etc/group:ro
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /etc/os-release:/host/etc/os-release:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      - NETDATA_CLAIM_TOKEN=${NETDATA_CLAIM_TOKEN:-}
      - NETDATA_CLAIM_URL=https://app.netdata.cloud

volumes:
  netdataconfig:
  netdatalib:
  netdatacache:
EOF

echo "✓ Docker Compose file created"

# 5. Install config ke nginx yang udah ada
echo "Installing netdata config to existing nginx..."
sudo cp netdata.conf /etc/nginx/conf.d/
sudo cp htpasswd-netdata /etc/nginx/.htpasswd-netdata

# Test nginx config
echo "Testing nginx configuration..."
sudo nginx -t
if [ $? -eq 0 ]; then
    echo "✓ Nginx configuration is valid"
    echo "Reloading nginx..."
    sudo systemctl reload nginx
    echo "✓ Nginx reloaded successfully"
else
    echo "✗ Nginx configuration has errors!"
    echo "Removing netdata config..."
    sudo rm -f /etc/nginx/conf.d/netdata.conf
    sudo rm -f /etc/nginx/.htpasswd-netdata
    exit 1
fi

# 6. Buat script untuk manage services
cat > manage.sh << 'EOF'
#!/bin/bash

case "$1" in
    start)
        echo "Starting Netdata with Nginx auth..."
        docker-compose up -d
        echo "✓ Services started"
        echo "Access: http://103.185.xxx.xxx:19999"
        echo "Username: admin"
        echo "Password: netdatanihbosku"
        ;;
    stop)
        echo "Stopping services..."
        docker-compose down
        echo "✓ Services stopped"
        ;;
    restart)
        echo "Restarting services..."
        docker-compose down
        docker-compose up -d
        echo "✓ Services restarted"
        ;;
    logs)
        docker-compose logs -f
        ;;
    status)
        docker-compose ps
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|logs|status}"
        exit 1
        ;;
esac
EOF

chmod +x manage.sh

echo "✓ Management script created"

# 7. Final info
echo ""
echo "=== SETUP COMPLETED ==="
echo "Files created:"
echo "- docker-compose.yml (netdata container)"
echo "- netdata.conf (installed to /etc/nginx/conf.d/)"
echo "- htpasswd-netdata (installed to /etc/nginx/)"
echo "- manage.sh"
echo ""
echo "To start netdata:"
echo "  ./manage.sh start"
echo ""
echo "Access URL: http://103.185.xxx.xxx:19999"
echo "Username: admin"
echo "Password: netdatanihbosku"
echo ""
echo "Other commands:"
echo "  ./manage.sh stop     - Stop netdata"
echo "  ./manage.sh restart  - Restart netdata"
echo "  ./manage.sh logs     - View logs"
echo "  ./manage.sh status   - Check status"
echo ""
echo "Note: Nginx config sudah ditambahkan ke existing setup"
echo "      Port 19999 akan di-proxy oleh nginx yang sudah ada"
