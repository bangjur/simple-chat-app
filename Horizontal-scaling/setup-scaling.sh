#!/bin/bash
# Horizontal Scaling Setup dengan Nginx + Consul
# Run this script as root

set -e

echo "=== Setting up Horizontal Scaling Infrastructure ==="

# 1. Create directory structure and make them writable
mkdir -p /etc/nginx/consul-templates
mkdir -p /opt/scaling/{scripts,logs}
mkdir -p /var/lib/consul

sudo mkdir -p /opt/scaling/nginx-config
sudo chmod 777 /opt/scaling/nginx-config

# 2. Install Docker Compose if not exists
if ! command -v docker-compose &> /dev/null; then
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# 3. Create Consul Template for Nginx Load Balancer
cat > /etc/nginx/consul-templates/load-balancer.conf.tpl << 'EOF'
upstream backend {
{{range service "web-app"}}
    server {{.Address}}:{{.Port}} max_fails=3 fail_timeout=30s;
{{end}}
    # Fallback ke default jika tidak ada backend
    server 127.0.0.1:8081 backup;
}

server {
    listen 80;
    server_name _;
    
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
        
        # Health check untuk backend
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
        proxy_connect_timeout 5s;
        proxy_send_timeout 10s;
        proxy_read_timeout 10s;
    }
}
EOF

# 4. Create fallback nginx app (backup server)
cat > /opt/scaling/scripts/fallback-app.py << 'EOF'
from flask import Flask
import os

app = Flask(__name__)

@app.route('/')
def home():
    return """
    <h1>Scaling Infrastructure</h1>
    <p>No backend servers available. Please wait for scaling...</p>
    <p>Server ID: fallback</p>
    """

@app.route('/health')
def health():
    return 'healthy'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8081)
EOF

# 5. Create stress test application
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
    
    return f'''
    <h1>Web Application - Container {{os.getenv("CONTAINER_ID", "unknown")}}</h1>
    <p>CPU Usage: {{cpu_percent}}%</p>
    <p>Memory Usage: {{memory.percent}}%</p>
    <p>Available Memory: {{memory.available / 1024 / 1024:.2f}} MB</p>
    <a href="/stress">Click here to stress test</a>
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
    
    return 'Stress test started! Check CPU and memory usage.'

@app.route('/health')
def health():
    return 'healthy'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
EOF

# 6. Create Docker Compose for infrastructure
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
      - /opt/scaling/nginx-config:/etc/nginx/conf.d
    command: >
      consul-template
      -template="/templates/load-balancer.conf.tpl:/etc/nginx/conf.d/load-balancer.conf:nginx -s reload"
      -consul-addr=consul:8500
      -log-level=INFO
    depends_on:
      - consul
    networks:
      - scaling_network
    restart: unless-stopped

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

# 7. Create monitoring and scaling script
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
    local container_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container_name")
    
    curl -s -X PUT "$CONSUL_URL/v1/agent/service/register" \
        -d "{\n            \"ID\": \"$container_name\",\n            \"Name\": \"web-app\",\n            \"Address\": \"$container_ip\",\n            \"Port\": $port,\n            \"Check\": {\n                \"HTTP\": \"http://$container_ip:$port/health\",\n                \"Interval\": \"10s\",\n                \"Timeout\": \"3s\"\n            }\n        }" && log "Registered $container_name to Consul"
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
    local new_port=$((5000 + CONTAINER_COUNT))
    
    log "Scaling up: Creating $new_container on port $new_port"
    
    # Create new container
    docker run -d \
        --name "$new_container" \
        --network scaling_network \
        -p "$new_port:5000" \
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
    docker stop "$container_to_remove"
    docker rm "$container_to_remove"
    
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

# Initialize: Register initial container
log "Starting monitoring and scaling service"
register_service "web-app-1" 5000

# Main monitoring loop
while true; do
    check_and_scale
    sleep $CHECK_INTERVAL
done
EOF

# 8. Create systemd service for monitoring
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

[Install]
WantedBy=multi-user.target
EOF

# 9. Make scripts executable
chmod +x /opt/scaling/scripts/*.sh

# 10. Install bc for floating point calculations
if ! command -v bc &> /dev/null; then
    if command -v yum &> /dev/null; then
        yum install -y bc
    elif command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y bc
    fi
fi

echo "=== Setup completed! ==="
echo ""
echo "Next steps:"
echo "1. cd /opt/scaling && docker-compose up -d"
echo "2. systemctl enable scaling-monitor.service"
echo "3. systemctl start scaling-monitor.service"
echo "4. Test: curl http://localhost/stress"
echo "5. Monitor: tail -f /opt/scaling/logs/scaling.log"
echo "6. Consul UI: http://localhost:8500"
echo ""
echo "Your existing nginx config will remain intact."
echo "Load balancer config will be added to /etc/nginx/conf.d/load-balancer.conf"
