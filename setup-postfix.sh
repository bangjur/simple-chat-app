#!/bin/bash

# Setup Postfix untuk Gmail SMTP di AlmaLinux
# Author: Assistant
# Usage: sudo bash setup-postfix.sh

set -e

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Fungsi untuk print dengan warna
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "Script ini harus dijalankan sebagai root"
   exit 1
fi

print_info "=== Setup Postfix untuk Gmail SMTP di AlmaLinux ==="

# Step 1: Install required packages
print_info "Step 1: Installing required packages..."
dnf install -y postfix cyrus-sasl-plain s-nail

# Step 2: Backup original config
print_info "Step 2: Backing up original config..."
cp /etc/postfix/main.cf /etc/postfix/main.cf.backup.$(date +%Y%m%d_%H%M%S)

# Step 3: Input Gmail credentials
print_info "Step 3: Setup Gmail credentials..."
read -p "Masukkan Gmail address: " GMAIL_USER
echo "Masukkan App Password Gmail (16 karakter tanpa spasi):"
read -s GMAIL_APP_PASSWORD
echo

# Validate app password format
if [[ ${#GMAIL_APP_PASSWORD} -ne 16 ]]; then
    print_warning "App password harus 16 karakter. Pastikan tidak ada spasi!"
fi

# Step 4: Configure Postfix main.cf
print_info "Step 4: Configuring Postfix main.cf..."

# Remove any existing Gmail configuration to avoid duplicates
sed -i '/^relayhost.*gmail/d' /etc/postfix/main.cf
sed -i '/^smtp_use_tls/d' /etc/postfix/main.cf
sed -i '/^smtp_sasl_auth_enable/d' /etc/postfix/main.cf
sed -i '/^smtp_sasl_password_maps/d' /etc/postfix/main.cf
sed -i '/^smtp_sasl_security_options/d' /etc/postfix/main.cf
sed -i '/^smtp_sasl_mechanism_filter/d' /etc/postfix/main.cf
sed -i '/^smtp_tls_security_level/d' /etc/postfix/main.cf
sed -i '/^smtp_generic_maps/d' /etc/postfix/main.cf

# Add Gmail SMTP configuration
cat >> /etc/postfix/main.cf << EOF

# Gmail SMTP Configuration
relayhost = [smtp.gmail.com]:587
smtp_use_tls = yes
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_tls_CAfile = /etc/pki/tls/certs/ca-bundle.crt
smtp_sasl_mechanism_filter = plain
smtp_tls_security_level = encrypt
smtp_generic_maps = hash:/etc/postfix/generic
EOF

# Step 5: Create SASL password file
print_info "Step 5: Creating SASL password file..."
cat > /etc/postfix/sasl_passwd << EOF
[smtp.gmail.com]:587 ${GMAIL_USER}:${GMAIL_APP_PASSWORD}
EOF

chmod 600 /etc/postfix/sasl_passwd
postmap /etc/postfix/sasl_passwd

# Step 6: Setup generic mapping (change sender from root to custom)
print_info "Step 6: Setting up generic mapping..."
read -p "Masukkan nama pengirim yang diinginkan (default: juriengine): " SENDER_NAME
SENDER_NAME=${SENDER_NAME:-juriengine}

HOSTNAME=$(hostname -f)
cat > /etc/postfix/generic << EOF
root@${HOSTNAME} ${SENDER_NAME}@${HOSTNAME}
EOF

postmap /etc/postfix/generic

# Step 7: Configure firewall
print_info "Step 7: Configuring firewall..."
if systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-port=587/tcp
    firewall-cmd --reload
    print_info "Firewall configured for SMTP port 587"
else
    print_warning "Firewalld tidak aktif, skip konfigurasi firewall"
fi

# Step 8: Enable and start Postfix
print_info "Step 8: Starting Postfix service..."
systemctl enable postfix
systemctl restart postfix

# Step 9: Validate configuration
print_info "Step 9: Validating configuration..."
postfix check

if [ $? -eq 0 ]; then
    print_info "Konfigurasi Postfix valid!"
else
    print_error "Ada error dalam konfigurasi Postfix!"
    exit 1
fi

# Step 10: Test email sending
print_info "Step 10: Testing email sending..."
read -p "Masukkan email tujuan untuk test: " TEST_EMAIL

echo "Sending test email..."
echo "Test email dari AlmaLinux server $(hostname) pada $(date)" | mail -s "Test Email dari ${SENDER_NAME}" "${TEST_EMAIL}"

print_info "Test email telah dikirim ke ${TEST_EMAIL}"
print_info "Cek email queue dengan: postqueue -p"
print_info "Monitor log dengan: journalctl -u postfix -f"

# Step 11: Show useful commands
print_info "=== Setup Selesai! ==="
echo
print_info "Useful commands:"
echo "  - Cek status: systemctl status postfix"
echo "  - Cek queue: postqueue -p"
echo "  - Flush queue: postqueue -f"
echo "  - Monitor log: journalctl -u postfix -f"
echo "  - Test kirim: echo 'test' | mail -s 'subject' email@domain.com"
echo
print_warning "Jika ada masalah, gunakan troubleshoot-postfix.md untuk debugging"

print_info "Setup completed successfully!"