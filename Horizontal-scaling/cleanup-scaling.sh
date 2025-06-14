#!/bin/bash
# Cleanup script untuk reset horizontal scaling infrastructure
# Run this before re-running setup-scaling.sh

set -e

echo "=== Cleaning up Horizontal Scaling Infrastructure ==="

# 1. Stop dan remove containers
echo "[INFO] Stopping and removing containers..."
cd /opt/scaling 2>/dev/null || true

if [ -f "docker-compose.yml" ]; then
    docker-compose down -v --remove-orphans 2>/dev/null || true
fi

# Stop individual containers if compose fails
for container in nginx-lb consul-template consul fallback-app $(docker ps -a --filter "name=web-app-" --format "{{.Names}}"); do
    if docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
        echo "  Stopping $container..."
        docker stop "$container" 2>/dev/null || true
        echo "  Removing $container..."
        docker rm "$container" 2>/dev/null || true
    fi
done

# 2. Remove custom network
echo "[INFO] Removing custom network..."
docker network rm scaling_network 2>/dev/null || true

# 3. Remove custom images
echo "[INFO] Removing custom images..."
docker rmi scaling_web-app:latest 2>/dev/null || true

# 4. Remove scaling folders (keep SSL certificates)
echo "[INFO] Removing scaling directories..."
rm -rf /opt/scaling/scripts
rm -rf /opt/scaling/logs  
rm -rf /opt/scaling/nginx-config
rm -f /opt/scaling/docker-compose.yml

# Keep SSL folder intact untuk avoid re-copying certificates
# rm -rf /opt/scaling/ssl  # <- Don't remove this

# 5. Remove consul templates
echo "[INFO] Removing consul templates..."
rm -rf /etc/nginx/consul-templates

# 6. Stop and disable scaling monitor service
echo "[INFO] Stopping scaling monitor service..."
systemctl stop scaling-monitor.service 2>/dev/null || true
systemctl disable scaling-monitor.service 2>/dev/null || true
rm -f /etc/systemd/system/scaling-monitor.service

# 7. Remove SSL renewal cron
echo "[INFO] Removing SSL renewal cron..."
rm -f /etc/cron.d/ssl-renewal

# 8. Reload systemd
systemctl daemon-reload

# 9. Prune unused docker resources
echo "[INFO] Cleaning up docker resources..."
docker system prune -f --volumes 2>/dev/null || true

# 10. Show what's left
echo ""
echo "=== Cleanup Summary ==="
echo "✅ Containers stopped and removed"
echo "✅ Custom network removed" 
echo "✅ Custom images removed"
echo "✅ Scaling directories cleaned"
echo "✅ Systemd service removed"
echo "✅ Cron jobs removed"
echo ""
echo "⚠️  Kept for re-use:"
echo "  • /opt/scaling/ssl/ (SSL certificates)"
echo "  • /opt/scaling/ (base directory)"
echo ""
echo "🚀 Ready to run setup-scaling.sh again!"

# Optional: Check if host nginx needs to be re-enabled
if ! systemctl is-active --quiet nginx && ls /etc/nginx/nginx.conf.backup.* 1> /dev/null 2>&1; then
    echo ""
    echo "💡 OPTIONAL: Re-enable host nginx if needed:"
    echo "   sudo systemctl enable nginx"
    echo "   sudo systemctl start nginx"
fi

echo ""
echo "🧹 Cleanup completed successfully!"
