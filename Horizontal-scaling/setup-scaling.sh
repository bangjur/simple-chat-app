#!/bin/bash
# Horizontal Scaling Setup dengan Nginx + Consul + SSL Support
# Run this script as root

set -e

echo "=== Setting up Horizontal Scaling Infrastructure with SSL ==="

# 1. Create directory structure and make them writable
mkdir -p /etc/nginx/consul-templates
mkdir -p /opt/scaling/{scripts,logs,ssl}
mkdir -p /var/lib/consul

sudo mkdir -p /opt/scaling/nginx-config
sudo chmod 777 /opt/scaling/nginx-config

# 2. Copy SSL certificates to scaling directory
echo "[INFO] Copying SSL certificates..."
if [ -d "/etc/letsencrypt/live" ]; then
    sudo cp -r /etc/letsencrypt/live /opt/scaling/ssl/
    sudo cp -r /etc/letsencrypt/archive /opt/scaling/ssl/
    sudo chmod -R 644 /opt/scaling/ssl/
    sudo find /opt/scaling/ssl/ -name "privkey*.pem" -exec chmod 600 {} \;
    echo "[INFO] SSL certificates copied successfully"
else
    echo "[WARNING] No SSL certificates found in /etc/letsencrypt/live"
    echo "[INFO] Creating self-signed certificate for testing..."
    mkdir -p /opt/scaling/ssl/live/juriengine.user.cloudjkt02.com
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /opt/scaling/ssl/live/juriengine.user.cloudjkt02.com/privkey.pem \
        -out /opt/scaling/ssl/live/juriengine.user.cloudjkt02.com/fullchain.pem \
        -subj "/C=ID/ST=Jakarta/L=Jakarta/O=JuriEngine/CN=juriengine.user.cloudjkt02.com"
    chmod 600 /opt/scaling/ssl/live/juriengine.user.cloudjkt02.com/privkey.pem
    chmod 644 /opt/scaling/ssl/live/juriengine.user.cloudjkt02.com/fullchain.pem
fi

# 3. Install Docker Compose if not exists
if ! command -v docker-compose &> /dev/null; then
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# 4. Create Consul Template for Nginx Load Balancer with SSL
cat > /etc/nginx/consul-templates/load-balancer.conf.tpl << 'EOF'
upstream backend {
{{range service "web-app"}}
    server {{.Address}}:{{.Port}} max_fails=3 fail_timeout=30s;
{{end}}
    # Fallback ke default jika tidak ada backend
    server fallback-app:8081 backup;
}

# HTTP Server - Redirect to HTTPS
server {
    listen 80;
    server_name _;
    
    # Health check endpoint (allow HTTP for monitoring)
    location /nginx-health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    # Redirect all other HTTP traffic to HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
}

# HTTPS Server
server {
    listen 443 ssl;
    server_name _;
    
    # Enable HTTP/2
    http2 on;
    
    # SSL Configuration
    ssl_certificate /etc/nginx/ssl/live/juriengine.user.cloudjkt02.com/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/live/juriengine.user.cloudjkt02.com/privkey.pem;
    
    # SSL Session Settings
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # SSL Protocols and Ciphers
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    
    # Health check endpoint
    location /nginx-health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    # Main application
    location / {
        proxy_pass http://backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Port $server_port;
        
        # Health check untuk backend
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
        proxy_connect_timeout 5s;
        proxy_send_timeout 10s;
        proxy_read_timeout 10s;
        
        # Buffer settings
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
    }
}
EOF

# 5. Create fallback nginx app (backup server)
cat > /opt/scaling/scripts/fallback-app.py << 'EOF'
from flask import Flask, request
import os

app = Flask(__name__)

@app.route('/')
def home():
    scheme = request.headers.get('X-Forwarded-Proto', 'http')
    host = request.headers.get('Host', 'localhost')
    
    return f"""
    <h1>Scaling Infrastructure</h1>
    <p>No backend servers available. Please wait for scaling...</p>
    <p>Server ID: fallback</p>
    <p>Protocol: {scheme}</p>
    <p>Host: {host}</p>
    <p>Headers: X-Forwarded-Proto = {request.headers.get('X-Forwarded-Proto', 'None')}</p>
    """

@app.route('/health')
def health():
    return 'healthy'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8081)
EOF

# 6. Create stress test application
cat > /opt/scaling/scripts/stress-app.py << 'EOF'
from flask import Flask, request
import time
import threading
import psutil
import os

app = Flask(__name__)

@app.route('/')
def home():
    cpu_percent = psutil.cpu_percent(interval=1)
    memory = psutil.virtual_memory()
    scheme = request.headers.get('X-Forwarded-Proto', 'http')
    host = request.headers.get('Host', 'localhost')
    
    return f'''
    <h1>Web Application - Container {os.getenv("CONTAINER_ID", "unknown")}</h1>
    <p>Protocol: {scheme}</p>
    <p>Host: {host}</p>
    <p>CPU Usage: {cpu_percent}%</p>
    <p>Memory Usage: {memory.percent}%</p>
    <p>Available Memory: {memory.available / 1024 / 1024:.2f} MB</p>
    <p><a href="/stress">Click here to stress test</a></p>
    <p><a href="/health">Health Check</a></p>
    <hr>
    <small>Headers: X-Forwarded-Proto = {request.headers.get('X-Forwarded-Proto', 'None')}</small>
    '''

@app.route('/stress')
def stress():
    # CPU intensive task
    def cpu_stress():
        end_time = time.time() + 120  # 120 seconds
        while time.time() < end_time:
            for i in range(2000000):
                _ = i ** 2

    # Memory intensive task
    def memory_stress():
        data = []
        end_time = time.time() + 120  # 120 seconds
        while time.time() < end_time:
            data.append('xyz' * 1024 * 1024)  # 1MB each
            time.sleep(0.01)

    # Run stress tests in background
    threading.Thread(target=cpu_stress).start()
    threading.Thread(target=memory_stress).start()
    
    return '''
    <h2>Stress test started!</h2>
    <p>Check CPU and memory usage for 2 minutes.</p>
    <p><a href="/">Back to home</a></p>
    '''

@app.route('/health')
def health():
    return 'healthy'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
EOF

# 7. Create Docker Compose for infrastructure with SSL support
cat > /opt/scaling/docker-compose.yml << 'EOF'
version: '3.8'

services:
  # Consul Service Discovery
  consul:
    image: consul:1.15
    container_name: consul
    ports:
      - "8500:8500"
    volumes:
      - consul_data:/consul/data
    command: >
      consul agent -dev -ui -client=0.0.0.0
      -log-level=INFO
    networks:
      - scaling_network
    restart: unless-stopped

  # Consul Template untuk auto-update nginx config
  consul-template:
    image: hashicorp/consul-template:0.32.0
    container_name: consul-template
    volumes:
      - /etc/nginx/consul-templates:/templates
      - /opt/scaling/nginx-config:/nginx-config
    command: >
      sh -c 'consul-template \
        -template="/templates/load-balancer.conf.tpl:/nginx-config/load-balancer.conf:docker exec nginx-lb nginx -s reload" \
        -consul-addr=consul:8500 \
        -log-level=INFO'
    depends_on:
      - consul
      - nginx-lb
    networks:
      - scaling_network
    restart: unless-stopped

  # Nginx Load Balancer (container) with SSL
  nginx-lb:
    image: nginx:1.25
    container_name: nginx-lb
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /opt/scaling/nginx-config:/etc/nginx/conf.d
      - /opt/scaling/ssl:/etc/nginx/ssl:ro
    networks:
      - scaling_network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/nginx-health"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Fallback application
  fallback-app:
    build:
      context: /opt/scaling/scripts
      dockerfile_inline: |
        FROM python:3.9-slim
        RUN pip install flask
        COPY fallback-app.py /app.py
        CMD ["python", "/app.py"]
    container_name: fallback-app
    ports:
      - "8081:8081"
    networks:
      - scaling_network
    restart: unless-stopped

  # Initial web application
  web-app-1:
    build:
      context: /opt/scaling/scripts
      dockerfile_inline: |
        FROM python:3.9-slim
        RUN pip install flask psutil
        COPY stress-app.py /app.py
        CMD ["python", "/app.py"]
    image: scaling_web-app:latest
    container_name: web-app-1
    ports:
      - "5000:5000"
    environment:
      - CONTAINER_ID=web-app-1
    networks:
      - scaling_network
    restart: unless-stopped

volumes:
  consul_data:

networks:
  scaling_network:
    driver: bridge
EOF

# 8. Backup existing nginx configuration
if [ -f "/etc/nginx/nginx.conf" ]; then
    echo "[INFO] Backing up existing nginx configuration..."
    cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup.$(date +%Y%m%d_%H%M%S)
fi

# 9. Stop and disable host nginx
if systemctl is-active --quiet nginx; then
    echo "[INFO] Stopping and disabling host nginx..."
    sudo systemctl stop nginx
    sudo systemctl disable nginx
    echo "[INFO] Host nginx stopped and disabled"
fi

# 10. Create monitoring and scaling script
cat > /opt/scaling/scripts/monitor-and-scale.sh << 'EOF'
#!/bin/bash

# Configuration
CONSUL_URL="http://localhost:8500"
CPU_THRESHOLD=85
MEMORY_THRESHOLD=85
CHECK_INTERVAL=10
SCALE_COOLDOWN=60
LOGFILE="/opt/scaling/logs/scaling.log"

# Global variables
LAST_SCALE_TIME=0
CONTAINER_COUNT=1

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

get_container_stats() {
    local container_name=$1
    docker stats --no-stream --format "table {{.CPUPerc}}\t{{.MemPerc}}" "$container_name" 2>/dev/null | tail -n +2
}

register_service() {
    local container_name=$1
    local port=$2
    local container_ip=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container_name" 2>/dev/null)
    
    if [ -z "$container_ip" ]; then
        log "Failed to get IP for $container_name"
        return 1
    fi
    
    curl -s -X PUT "$CONSUL_URL/v1/agent/service/register" \
        -d "{
            \"ID\": \"$container_name\",
            \"Name\": \"web-app\",
            \"Address\": \"$container_ip\",
            \"Port\": $port,
            \"Check\": {
                \"HTTP\": \"http://$container_ip:$port/health\",
                \"Interval\": \"10s\",
                \"Timeout\": \"3s\"
            }
        }" && log "Registered $container_name to Consul ($container_ip:$port)"
}

deregister_service() {
    local container_name=$1
    curl -s -X PUT "$CONSUL_URL/v1/agent/service/deregister/$container_name" \
        && log "Deregistered $container_name from Consul"
}

scale_up() {
    local current_time=$(date +%s)
    if [ $((current_time - LAST_SCALE_TIME)) -lt $SCALE_COOLDOWN ]; then
        log "Scale cooldown active, skipping scale up"
        return
    fi
    
    CONTAINER_COUNT=$((CONTAINER_COUNT + 1))
    local new_container="web-app-$CONTAINER_COUNT"
    
    log "Scaling up: Creating $new_container"
    
    # Create new container
    docker run -d \
        --name "$new_container" \
        --network scaling_network \
        -e CONTAINER_ID="$new_container" \
        scaling_web-app:latest
    
    if [ $? -ne 0 ]; then
        log "Failed to start $new_container"
        CONTAINER_COUNT=$((CONTAINER_COUNT - 1))
        return
    fi
    
    # Wait for container to be ready
    sleep 5
    
    # Register to Consul
    register_service "$new_container" 5000
    
    LAST_SCALE_TIME=$current_time
    log "Successfully scaled up to $CONTAINER_COUNT containers"
}

scale_down() {
    if [ $CONTAINER_COUNT -le 1 ]; then
        log "Cannot scale down below 1 container"
        return
    fi
    
    local container_to_remove="web-app-$CONTAINER_COUNT"
    
    log "Scaling down: Removing $container_to_remove"
    
    # Deregister from Consul
    deregister_service "$container_to_remove"
    
    # Wait for consul to propagate
    sleep 10
    
    # Stop and remove container
    docker stop "$container_to_remove" >/dev/null 2>&1
    docker rm "$container_to_remove" >/dev/null 2>&1
    
    CONTAINER_COUNT=$((CONTAINER_COUNT - 1))
    log "Successfully scaled down to $CONTAINER_COUNT containers"
}

check_and_scale() {
    local total_cpu=0
    local total_memory=0
    local active_containers=0
    
    # Check all web-app containers
    for container in $(docker ps --filter "name=web-app-" --format "{{.Names}}"); do
        local stats=$(get_container_stats "$container")
        if [ -n "$stats" ]; then
            local cpu=$(echo "$stats" | awk '{print $1}' | sed 's/%//')
            local memory=$(echo "$stats" | awk '{print $2}' | sed 's/%//')
            
            total_cpu=$(echo "scale=2; $total_cpu + $cpu" | bc)
            total_memory=$(echo "scale=2; $total_memory + $memory" | bc)
            active_containers=$((active_containers + 1))
            
            log "Container $container - CPU: ${cpu}%, Memory: ${memory}%"
        fi
    done
    
    if [ $active_containers -eq 0 ]; then
        log "No active containers found"
        return
    fi
    
    # Calculate average
    local avg_cpu=$(echo "scale=2; $total_cpu / $active_containers" | bc)
    local avg_memory=$(echo "scale=2; $total_memory / $active_containers" | bc)
    
    log "Average - CPU: ${avg_cpu}%, Memory: ${avg_memory}%"
    
    # Scale decision
    if (( $(echo "$avg_cpu > $CPU_THRESHOLD" | bc -l) )) || (( $(echo "$avg_memory > $MEMORY_THRESHOLD" | bc -l) )); then
        log "High resource usage detected - triggering scale up"
        scale_up
    elif (( $(echo "$avg_cpu < 30" | bc -l) )) && (( $(echo "$avg_memory < 30" | bc -l) )) && [ $active_containers -gt 1 ]; then
        log "Low resource usage detected - triggering scale down"
        scale_down
    fi
}

# Wait for consul to be ready
wait_for_consul() {
    log "Waiting for Consul to be ready..."
    while ! curl -s "$CONSUL_URL/v1/status/leader" >/dev/null 2>&1; do
        sleep 5
    done
    log "Consul is ready"
}

# Main function
main() {
    log "Starting monitoring and scaling service"
    
    # Wait for consul
    wait_for_consul
    
    # Initialize: Register initial container
    sleep 10  # Wait for container to be fully ready
    register_service "web-app-1" 5000
    
    # Main monitoring loop
    while true; do
        check_and_scale
        sleep $CHECK_INTERVAL
    done
}

# Handle script termination
cleanup() {
    log "Shutting down monitoring service"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Run main function
main
EOF

# 11. Create systemd service for monitoring
cat > /etc/systemd/system/scaling-monitor.service << 'EOF'
[Unit]
Description=Container Scaling Monitor
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/scaling
ExecStart=/opt/scaling/scripts/monitor-and-scale.sh
Restart=always
RestartSec=10
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

# 12. Create SSL certificate renewal script
cat > /opt/scaling/scripts/renew-ssl.sh << 'EOF'
#!/bin/bash
# SSL Certificate Renewal Script

echo "Renewing SSL certificates..."

# Renew certificates using certbot
certbot renew --quiet

# Copy renewed certificates to scaling directory
if [ $? -eq 0 ]; then
    echo "Copying renewed certificates..."
    cp -r /etc/letsencrypt/live /opt/scaling/ssl/
    cp -r /etc/letsencrypt/archive /opt/scaling/ssl/
    chmod -R 644 /opt/scaling/ssl/
    find /opt/scaling/ssl/ -name "privkey*.pem" -exec chmod 600 {} \;
    
    # Reload nginx container
    docker exec nginx-lb nginx -s reload
    echo "SSL certificates renewed and nginx reloaded"
else
    echo "Certificate renewal failed"
fi
EOF

# 13. Make scripts executable
chmod +x /opt/scaling/scripts/*.sh

# 14. Install bc for floating point calculations
if ! command -v bc &> /dev/null; then
    if command -v yum &> /dev/null; then
        yum install -y bc curl
    elif command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y bc curl
    fi
fi

# 15. Create log directory
mkdir -p /opt/scaling/logs

# 16. Set up cron job for SSL renewal (optional)
echo "0 3 * * 0 /opt/scaling/scripts/renew-ssl.sh >> /opt/scaling/logs/ssl-renewal.log 2>&1" | crontab -

echo "=== Setup completed! ==="
echo ""
echo "SSL-enabled Horizontal Scaling Setup:"
echo "1. cd /opt/scaling && docker-compose up -d"
echo "2. systemctl daemon-reload"
echo "3. systemctl enable scaling-monitor.service"
echo "4. systemctl start scaling-monitor.service"
echo ""
echo "Testing:"
echo "5. HTTP (redirects to HTTPS): curl -I http://localhost/"
echo "6. HTTPS: curl -k https://localhost/"
echo "7. Stress test: curl -k https://localhost/stress"
echo "8. Monitor logs: tail -f /opt/scaling/logs/scaling.log"
echo "9. Consul UI: http://localhost:8500"
echo ""
echo "SSL Configuration:"
echo "- Certificates: /opt/scaling/ssl/"
echo "- HTTP automatically redirects to HTTPS"
echo "- SSL renewal script: /opt/scaling/scripts/renew-ssl.sh"
echo "- Cron job added for weekly SSL renewal"
echo ""
echo "Your host nginx has been stopped and disabled."
echo "The containerized nginx will handle both HTTP and HTTPS traffic."
