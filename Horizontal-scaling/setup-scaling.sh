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

# 2. Install Docker Compose if not exists
if ! command -v docker-compose &> /dev/null; then
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# 3. Copy SSL certificates from existing nginx setup
echo "[INFO] Copying SSL certificates..."
if [ -d "/etc/letsencrypt/live/juriengine.user.cloudjkt02.com" ]; then
    cp -r /etc/letsencrypt/live/juriengine.user.cloudjkt02.com /opt/scaling/ssl/
    # Also copy renewal config and archive for future renewals
    mkdir -p /opt/scaling/ssl/renewal
    if [ -f "/etc/letsencrypt/renewal/juriengine.user.cloudjkt02.com.conf" ]; then
        cp /etc/letsencrypt/renewal/juriengine.user.cloudjkt02.com.conf /opt/scaling/ssl/renewal/
    fi
    echo "[INFO] SSL certificates copied successfully"
else
    echo "[WARNING] SSL certificates not found at /etc/letsencrypt/live/juriengine.user.cloudjkt02.com"
    echo "[INFO] You may need to setup SSL certificates manually"
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

# HTTP server - redirect to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name _;
    
    # Health check endpoint (allow HTTP for monitoring)
    location /nginx-health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    # Redirect all other traffic to HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name _;
    
    # SSL Configuration
    ssl_certificate /etc/nginx/ssl/juriengine.user.cloudjkt02.com/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/juriengine.user.cloudjkt02.com/privkey.pem;
    
    ssl_session_cache shared:SSL:1m;
    ssl_session_timeout 10m;
    ssl_ciphers PROFILE=SYSTEM;
    ssl_prefer_server_ciphers on;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    
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
        proxy_set_header X-Forwarded-Host $host;
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
        proxy_busy_buffers_size 8k;
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
    return f"""
    <h1>Scaling Infrastructure - Maintenance Mode</h1>
    <p>No backend servers available. Please wait for scaling...</p>
    <p>Server ID: fallback</p>
    <p>Protocol: {request.headers.get('X-Forwarded-Proto', 'http')}</p>
    <p>Host: {request.headers.get('Host', 'unknown')}</p>
    <style>
        body {{ font-family: Arial, sans-serif; text-align: center; margin-top: 50px; }}
        h1 {{ color: #ff6b35; }}
    </style>
    """

@app.route('/health')
def health():
    return 'healthy'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8081)
EOF

# 6. Create stress test application with HTTPS awareness
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
    protocol = request.headers.get('X-Forwarded-Proto', 'http')
    
    return f'''
    <h1>Web Application - Container {os.getenv("CONTAINER_ID", "unknown")}</h1>
    <p><strong>Protocol:</strong> {protocol.upper()}</p>
    <p><strong>Host:</strong> {request.headers.get('Host', 'unknown')}</p>
    <p><strong>CPU Usage:</strong> {cpu_percent}%</p>
    <p><strong>Memory Usage:</strong> {memory.percent}%</p>
    <p><strong>Available Memory:</strong> {memory.available / 1024 / 1024:.2f} MB</p>
    <p><strong>Container IP:</strong> {request.headers.get('X-Real-IP', 'unknown')}</p>
    <hr>
    <a href="/stress" style="background: #ff6b35; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px;">
        🔥 Start Stress Test
    </a>
    <style>
        body {{ font-family: Arial, sans-serif; max-width: 600px; margin: 50px auto; padding: 20px; }}
        h1 {{ color: #333; border-bottom: 2px solid #ff6b35; }}
        p {{ margin: 10px 0; }}
    </style>
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
            data.append('x' * 1024 * 1024)  # 1MB each
            time.sleep(0.01)

    # Run stress tests in background
    threading.Thread(target=cpu_stress, daemon=True).start()
    threading.Thread(target=memory_stress, daemon=True).start()
    
    return '''
    <h1>🔥 Stress Test Started!</h1>
    <p>CPU and Memory stress test is now running for 2 minutes.</p>
    <p>Check the monitoring logs to see auto-scaling in action!</p>
    <a href="/">← Back to Status</a>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; margin-top: 100px; }
        h1 { color: #ff6b35; }
    </style>
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
    healthcheck:
      test: ["CMD", "consul", "members"]
      interval: 10s
      timeout: 3s
      retries: 3

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
        -log-level=INFO \
        -wait="2s:10s"'
    depends_on:
      consul:
        condition: service_healthy
      nginx-lb:
        condition: service_started
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
        EXPOSE 8081
        CMD ["python", "/app.py"]
    container_name: fallback-app
    ports:
      - "8081:8081"
    networks:
      - scaling_network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8081/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Initial web application
  web-app-1:
    build:
      context: /opt/scaling/scripts
      dockerfile_inline: |
        FROM python:3.9-slim
        RUN pip install flask psutil
        COPY stress-app.py /app.py
        EXPOSE 5000
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
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/health"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  consul_data:

networks:
  default:
    name: scaling_network
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
EOF

# 8. Disable nginx host dan backup config
if systemctl is-active --quiet nginx; then
  echo "[INFO] Backing up and disabling host nginx..."
  # Backup current config
  cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup.$(date +%Y%m%d_%H%M%S)
  sudo systemctl stop nginx
  sudo systemctl disable nginx
  echo "[INFO] Host nginx disabled. Backup created."
fi

# 9. Create monitoring and scaling script dengan SSL awareness
cat > /opt/scaling/scripts/monitor-and-scale.sh << 'EOF'
#!/bin/bash

# Configuration
CONSUL_URL="http://localhost:8500"
CPU_THRESHOLD=75
MEMORY_THRESHOLD=75
CHECK_INTERVAL=15
SCALE_COOLDOWN=60
LOGFILE="/opt/scaling/logs/scaling.log"
MAX_CONTAINERS=5
MIN_CONTAINERS=1

# Global variables
LAST_SCALE_TIME=0
CONTAINER_COUNT=1

# Create log directory
mkdir -p "$(dirname "$LOGFILE")"

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
    local container_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container_name" 2>/dev/null)
    
    if [ -z "$container_ip" ]; then
        log "ERROR: Could not get IP for $container_name"
        return 1
    fi
    
    local registration_data=$(cat <<JSON
{
    "ID": "$container_name",
    "Name": "web-app",
    "Address": "$container_ip",
    "Port": $port,
    "Check": {
        "HTTP": "http://$container_ip:$port/health",
        "Interval": "15s",
        "Timeout": "5s",
        "DeregisterCriticalServiceAfter": "60s"
    }
}
JSON
)
    
    curl -s -X PUT "$CONSUL_URL/v1/agent/service/register" \
        -H "Content-Type: application/json" \
        -d "$registration_data" && log "✓ Registered $container_name ($container_ip:$port) to Consul"
}

deregister_service() {
    local container_name=$1
    curl -s -X PUT "$CONSUL_URL/v1/agent/service/deregister/$container_name" \
        && log "✗ Deregistered $container_name from Consul"
}

wait_for_container_ready() {
    local container_name=$1
    local max_attempts=30
    local attempt=0
    
    log "Waiting for $container_name to be ready..."
    while [ $attempt -lt $max_attempts ]; do
        if docker exec "$container_name" curl -s http://localhost:5000/health >/dev/null 2>&1; then
            log "✓ $container_name is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    log "✗ $container_name failed to become ready after $max_attempts attempts"
    return 1
}

scale_up() {
    if [ $CONTAINER_COUNT -ge $MAX_CONTAINERS ]; then
        log "Maximum containers ($MAX_CONTAINERS) reached, cannot scale up"
        return
    fi
    
    local current_time=$(date +%s)
    if [ $((current_time - LAST_SCALE_TIME)) -lt $SCALE_COOLDOWN ]; then
        log "Scale cooldown active ($(($SCALE_COOLDOWN - (current_time - LAST_SCALE_TIME)))s remaining), skipping scale up"
        return
    fi
    
    CONTAINER_COUNT=$((CONTAINER_COUNT + 1))
    local new_container="web-app-$CONTAINER_COUNT"
    
    log "🚀 Scaling UP: Creating $new_container (Total: $CONTAINER_COUNT containers)"
    
    # Create new container
    docker run -d \
        --name "$new_container" \
        --network scaling_network \
        -e CONTAINER_ID="$new_container" \
        --health-cmd="curl -f http://localhost:5000/health || exit 1" \
        --health-interval=30s \
        --health-timeout=10s \
        --health-retries=3 \
        scaling_web-app:latest
    
    if [ $? -ne 0 ]; then
        log "✗ Failed to start $new_container"
        CONTAINER_COUNT=$((CONTAINER_COUNT - 1))
        return
    fi
    
    # Wait for container to be ready
    if ! wait_for_container_ready "$new_container"; then
        log "✗ $new_container failed health check, removing..."
        docker stop "$new_container" && docker rm "$new_container"
        CONTAINER_COUNT=$((CONTAINER_COUNT - 1))
        return
    fi
    
    # Register to Consul
    register_service "$new_container" 5000
    
    LAST_SCALE_TIME=$current_time
    log "✅ Successfully scaled UP to $CONTAINER_COUNT containers"
}

scale_down() {
    if [ $CONTAINER_COUNT -le $MIN_CONTAINERS ]; then
        log "Minimum containers ($MIN_CONTAINERS) reached, cannot scale down"
        return
    fi
    
    local container_to_remove="web-app-$CONTAINER_COUNT"
    
    log "🔽 Scaling DOWN: Removing $container_to_remove (Total will be: $((CONTAINER_COUNT - 1)) containers)"
    
    # Deregister from Consul
    deregister_service "$container_to_remove"
    
    # Wait for consul to propagate changes
    log "Waiting for Consul to propagate changes..."
    sleep 15
    
    # Gracefully stop container
    log "Stopping $container_to_remove..."
    docker stop "$container_to_remove" --time=10
    docker rm "$container_to_remove"
    
    CONTAINER_COUNT=$((CONTAINER_COUNT - 1))
    log "✅ Successfully scaled DOWN to $CONTAINER_COUNT containers"
}

check_and_scale() {
    local total_cpu=0
    local total_memory=0
    local active_containers=0
    local high_load_containers=0
    
    log "🔍 Checking container metrics..."
    
    # Check all web-app containers
    for container in $(docker ps --filter "name=web-app-" --format "{{.Names}}"); do
        local stats=$(get_container_stats "$container")
        if [ -n "$stats" ]; then
            local cpu=$(echo "$stats" | awk '{print $1}' | sed 's/%//')
            local memory=$(echo "$stats" | awk '{print $2}' | sed 's/%//')
            
            # Handle case where stats might be empty or invalid
            if [[ "$cpu" =~ ^[0-9]+\.?[0-9]*$ ]] && [[ "$memory" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                total_cpu=$(echo "scale=2; $total_cpu + $cpu" | bc -l)
                total_memory=$(echo "scale=2; $total_memory + $memory" | bc -l)
                active_containers=$((active_containers + 1))
                
                # Count high load containers
                if (( $(echo "$cpu > $CPU_THRESHOLD" | bc -l) )) || (( $(echo "$memory > $MEMORY_THRESHOLD" | bc -l) )); then
                    high_load_containers=$((high_load_containers + 1))
                fi
                
                log "  📊 $container - CPU: ${cpu}%, Memory: ${memory}%"
            else
                log "  ⚠️  $container - Invalid stats received"
            fi
        else
            log "  ❌ $container - No stats available"
        fi
    done
    
    if [ $active_containers -eq 0 ]; then
        log "❌ No active containers found - this shouldn't happen!"
        return
    fi
    
    # Calculate averages
    local avg_cpu=$(echo "scale=2; $total_cpu / $active_containers" | bc -l)
    local avg_memory=$(echo "scale=2; $total_memory / $active_containers" | bc -l)
    
    log "📈 Cluster Summary:"
    log "  • Active Containers: $active_containers"
    log "  • Average CPU: ${avg_cpu}%"
    log "  • Average Memory: ${avg_memory}%"
    log "  • High Load Containers: $high_load_containers"
    
    # Enhanced scaling decision logic
    if (( $(echo "$avg_cpu > $CPU_THRESHOLD" | bc -l) )) || (( $(echo "$avg_memory > $MEMORY_THRESHOLD" | bc -l) )); then
        log "🔥 HIGH LOAD DETECTED - Triggering scale UP"
        scale_up
    elif [ $high_load_containers -gt $((active_containers / 2)) ] && [ $active_containers -lt $MAX_CONTAINERS ]; then
        log "📊 Multiple containers under high load - Triggering scale UP"
        scale_up
    elif (( $(echo "$avg_cpu < 25" | bc -l) )) && (( $(echo "$avg_memory < 25" | bc -l) )) && [ $active_containers -gt $MIN_CONTAINERS ]; then
        local current_time=$(date +%s)
        if [ $((current_time - LAST_SCALE_TIME)) -gt $((SCALE_COOLDOWN * 2)) ]; then
            log "📉 LOW LOAD DETECTED - Triggering scale DOWN"
            scale_down
        else
            log "⏳ Low load detected but still in cooldown period"
        fi
    fi
}

# Wait for services to be ready
wait_for_services() {
    log "⏳ Waiting for Consul to be ready..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -s "$CONSUL_URL/v1/status/leader" >/dev/null 2>&1; then
            log "✅ Consul is ready"
            break
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    if [ $attempt -eq $max_attempts ]; then
        log "❌ Consul failed to become ready"
        exit 1
    fi
}

# Initialize
log "🚀 Starting Horizontal Scaling Monitor with SSL Support"
log "Configuration:"
log "  • CPU Threshold: ${CPU_THRESHOLD}%"
log "  • Memory Threshold: ${MEMORY_THRESHOLD}%"
log "  • Check Interval: ${CHECK_INTERVAL}s"
log "  • Scale Cooldown: ${SCALE_COOLDOWN}s"
log "  • Min Containers: $MIN_CONTAINERS"
log "  • Max Containers: $MAX_CONTAINERS"

wait_for_services

# Register initial container
log "🔗 Registering initial container..."
register_service "web-app-1" 5000

# Main monitoring loop
log "🔄 Starting monitoring loop..."
while true; do
    check_and_scale
    log "💤 Sleeping for ${CHECK_INTERVAL} seconds..."
    echo "---"
    sleep $CHECK_INTERVAL
done
EOF

# 10. Create systemd service for monitoring
cat > /etc/systemd/system/scaling-monitor.service << 'EOF'
[Unit]
Description=Container Scaling Monitor with SSL Support
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/scaling
ExecStart=/opt/scaling/scripts/monitor-and-scale.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 11. Create SSL certificate renewal script
cat > /opt/scaling/scripts/renew-ssl.sh << 'EOF'
#!/bin/bash
# SSL Certificate Renewal Script for Containerized Nginx

DOMAIN="juriengine.user.cloudjkt02.com"
CERT_PATH="/opt/scaling/ssl/$DOMAIN"
LOG_FILE="/opt/scaling/logs/ssl-renewal.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log "Starting SSL certificate renewal check..."

# Check if certificates need renewal (less than 30 days)
if openssl x509 -checkend 2592000 -noout -in "$CERT_PATH/cert.pem" >/dev/null 2>&1; then
    log "Certificate is still valid for more than 30 days"
    exit 0
fi

log "Certificate needs renewal, stopping containerized nginx..."

# Stop containerized nginx temporarily
docker stop nginx-lb

# Renew certificate using host certbot
certbot renew --standalone --preferred-challenges http

# Copy renewed certificates
if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    cp -r "/etc/letsencrypt/live/$DOMAIN/"* "$CERT_PATH/"
    log "Certificates copied successfully"
else
    log "ERROR: Renewed certificates not found!"
fi

# Restart containerized nginx
docker start nginx-lb

log "SSL certificate renewal completed"
EOF

chmod +x /opt/scaling/scripts/renew-ssl.sh

# 12. Create SSL renewal cron job
cat > /etc/cron.d/ssl-renewal << 'EOF'
# SSL Certificate Renewal for Containerized Nginx
0 3 * * 0 root /opt/scaling/scripts/renew-ssl.sh >/dev/null 2>&1
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

echo "=== SSL-enabled Horizontal Scaling Setup Completed! ==="
echo ""
echo "🔥 Next steps:"
echo "1. cd /opt/scaling && docker-compose up -d"
echo "2. systemctl daemon-reload"
echo "3. systemctl enable scaling-monitor.service" 
echo "4. systemctl start scaling-monitor.service"
echo ""
echo "🧪 Testing:"
echo "• HTTP (redirects to HTTPS): curl -I http://your-domain/"
echo "• HTTPS: curl -k https://your-domain/"
echo "• Stress test: curl -k https://your-domain/stress"
echo "• Health check: curl http://localhost/nginx-health"
echo ""
echo "📊 Monitoring:"
echo "• Scaling logs: tail -f /opt/scaling/logs/scaling.log"
echo "• Consul UI: http://localhost:8500"
echo "• Container stats: docker stats"
echo ""
echo "🔒 SSL Notes:"
echo "• Certificates copied to /opt/scaling/ssl/"
echo "• Auto-renewal configured via cron (Sundays 3 AM)"
echo "• Manual renewal: /opt/scaling/scripts/renew-ssl.sh"
echo ""
echo "⚠️  Your host nginx has been disabled and backed up."
echo "   The containerized nginx now handles all traffic with SSL."
