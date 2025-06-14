# Netdata Setup Guide

This guide explains how to set up Netdata monitoring with Nginx authentication using Docker. The setup includes secure access through Nginx with basic authentication.

## Prerequisites

- Linux server with root access
- Docker and Docker Compose installed
- Nginx (non-container) installed and running
- Public IP address for your server

## Configuration Files

The setup script will create the following files:
- `docker-compose.yml` - Container configuration for Netdata
- `netdata.conf` - Nginx reverse proxy configuration
- `manage.sh` - Service management script

## Important Security Note

Before running the script:
1. Replace `103.185.xxx.xxx` with your server's actual public IP address
2. Change the default credentials:
   - Username: `admin`
   - Password: `netdatanihbosku`

⚠️ Using default credentials in production is a security risk!

## Setup Steps

### 1. Prepare the Script

1. Upload `setup-netdata.sh` to your server
2. Make it executable:
```bash
chmod +x setup-netdata.sh
```

### 2. Run the Setup Script

Execute the script:
```bash
./setup-netdata.sh
```

The script will:
- Create necessary directories and configurations
- Set up Nginx authentication
- Create Docker Compose configuration
- Install Nginx configs
- Generate management script

### 3. Using the Management Script

After setup completes, use `manage.sh` to control the service:

```bash
# Start Netdata
./manage.sh start

# Stop Netdata
./manage.sh stop

# Restart the service
./manage.sh restart

# View logs
./manage.sh logs

# Check service status
./manage.sh status
```

## Accessing Netdata

Once running, access your Netdata dashboard:

1. Open your browser
2. Navigate to `http://YOUR_SERVER_IP:19999`
3. Enter your credentials when prompted

## Configuration Details

### Ports
- External port: 19999 (Nginx)
- Internal port: 19998 (Netdata container)

### Security Features
- Basic authentication through Nginx
- Health check endpoint without authentication
- Security headers enabled:
  - X-Frame-Options
  - X-Content-Type-Options
  - X-XSS-Protection

### Volume Mounts
The container is configured with the following mounts:
- Netdata configuration: `/etc/netdata`
- Library data: `/var/lib/netdata`
- Cache data: `/var/cache/netdata`
- System information (read-only):
  - `/etc/passwd`
  - `/etc/group`
  - `/proc`
  - `/sys`
  - `/etc/os-release`
  - Docker socket

## Troubleshooting

If you encounter issues:
1. Check Nginx configuration validity:
   ```bash
   sudo nginx -t
   ```
2. View Netdata logs:
   ```bash
   ./manage.sh logs
   ```
3. Verify Nginx is running:
   ```bash
   sudo systemctl status nginx
   ```

## Email Alert Configuration

To configure email notifications for alerts:

1. First, check if the configuration file exists:
```bash
ls /etc/netdata/health_alarm_notify.conf
```

2. If the file doesn't exist, copy it from the original:
```bash
cp /etc/netdata/orig/health_alarm_notify.conf /etc/netdata/health_alarm_notify.conf
```

3. Edit the notification settings:
```bash
sudo nano /etc/netdata/health_alarm_notify.conf
```

4. Locate and modify these lines:
```conf
# Email sender and recipient
EMAIL_SENDER="netdata@yourdomain.com"
DEFAULT_RECIPIENT_EMAIL="your-mail@yourdomain.com"
```

Replace with your actual email addresses:
- `netdata@yourdomain.com` - The sender email address
- `your-mail@yourdomain.com` - The recipient email address where alerts will be sent

5. Save the file and restart Netdata using the management script:
```bash
./manage.sh restart
```

## Notes

- The setup creates a secure configuration by default
- All sensitive data should be changed before deploying to production
- Regular updates are recommended for security
- Backup your configuration files after customization
