# Troubleshooting Postfix Gmail SMTP

## 🔍 Quick Diagnosis Commands

### Cek Status Postfix
```bash
systemctl status postfix
```

### Cek Konfigurasi Aktif
```bash
postconf -n | grep -E "(relay|smtp_|sasl)"
```

### Cek Log Real-time
```bash
journalctl -u postfix -f
```

### Cek Email Queue
```bash
postqueue -p
```

### Validasi Konfigurasi
```bash
postfix check
```

---

## ⚠️ Warning: Duplikasi Konfigurasi

### Masalah Umum: smtp_tls_security_level Duplikat

**Gejala:**
```
postfix: warning: /etc/postfix/main.cf, line 746: overriding earlier entry: smtp_tls_security_level=encrypt
```

**Cara Cek Lokasi Duplikat:**
```bash
grep -n "smtp_tls_security_level" /etc/postfix/main.cf
```

**Solusi:**
```bash
# Backup dulu
sudo cp /etc/postfix/main.cf /etc/postfix/main.cf.backup

# Hapus semua duplikat
sudo sed -i '/^smtp_tls_security_level/d' /etc/postfix/main.cf

# Tambahkan hanya satu
echo "smtp_tls_security_level = encrypt" >> /etc/postfix/main.cf

# Restart
sudo systemctl restart postfix
```

### Cek Semua Konfigurasi Duplikat
```bash
# Cek duplikat di seluruh file
sort /etc/postfix/main.cf | uniq -d

# Atau cek parameter specific
grep -n "smtp_" /etc/postfix/main.cf | sort
```

---

## 🔐 App Password Gmail

### ❌ Format Salah
```
# SALAH - dengan spasi
pkrk dnvk xxxx xxxx

# SALAH - dengan tanda hubung
pkrk-dnvk-xxxx-xxxx
```

### ✅ Format Benar
```
# BENAR - 16 karakter tanpa spasi/tanda hubung
pkrkdnvkxxxxxxxx
```

### Cara Buat App Password Baru
1. Login ke Google Account → Security
2. 2-Step Verification → App passwords
3. Pilih "Mail" → Generate
4. Copy 16 karakter tanpa spasi

---

## 🚨 Error Messages & Solutions

### 1. SASL Authentication Failed
**Error:**
```
SASL authentication failed; server smtp.gmail.com said: 535-5.7.8 Username and Password not accepted
```

**Solusi:**
```bash
# 1. Cek format app password
cat /etc/postfix/sasl_passwd

# 2. Buat app password baru di Gmail
# 3. Update file
sudo nano /etc/postfix/sasl_passwd
# Format: [smtp.gmail.com]:587 user@gmail.com:16karakterapppassword

# 4. Rebuild database
sudo postmap /etc/postfix/sasl_passwd
sudo systemctl restart postfix
```

### 2. Connection Refused
**Error:**
```
connect to smtp.gmail.com[142.250.4.109]:587: Connection refused
```

**Solusi:**
```bash
# 1. Cek firewall
sudo firewall-cmd --list-ports
sudo firewall-cmd --permanent --add-port=587/tcp
sudo firewall-cmd --reload

# 2. Test koneksi manual
telnet smtp.gmail.com 587
```

### 3. TLS/SSL Errors
**Error:**
```
TLS is required, but was not offered by host
```

**Solusi:**
```bash
# Pastikan TLS config benar
sudo postconf -e "smtp_tls_security_level = encrypt"
sudo postconf -e "smtp_use_tls = yes"
sudo systemctl restart postfix
```

### 4. Certificate Errors
**Error:**
```
certificate verification failed
```

**Solusi:**
```bash
# Update CA certificates
sudo dnf update ca-certificates
sudo postconf -e "smtp_tls_CAfile = /etc/pki/tls/certs/ca-bundle.crt"
sudo systemctl restart postfix
```

---

## 📧 Testing Email

### Kirim Test Email
```bash
# Method 1: menggunakan mail
echo "Test body" | mail -s "Test Subject" recipient@domain.com

# Method 2: menggunakan s-nail
echo "Test body" | s-nail -s "Test Subject" recipient@domain.com

# Method 3: menggunakan sendmail
cat << EOF | sendmail recipient@domain.com
Subject: Test Email
From: sender@domain.com
To: recipient@domain.com

Test email body
EOF
```

### Cek Status Pengiriman
```bash
# Cek queue
postqueue -p

# Force flush queue
postqueue -f

# Cek log pengiriman
journalctl -u postfix | grep "recipient@domain.com"
```

---

## 🔧 File Locations

### Konfigurasi Utama
- `/etc/postfix/main.cf` - Konfigurasi utama Postfix
- `/etc/postfix/sasl_passwd` - Username/password Gmail
- `/etc/postfix/generic` - Mapping pengirim email

### Database Files
- `/etc/postfix/sasl_passwd.db` - Database password (auto-generated)
- `/etc/postfix/generic.db` - Database mapping (auto-generated)

### Log Files
- `/var/log/messages` - Log sistem umum
- `journalctl -u postfix` - Log khusus Postfix

---

## 🛠️ Maintenance Commands

### Rebuild Database
```bash
sudo postmap /etc/postfix/sasl_passwd
sudo postmap /etc/postfix/generic
```

### Restart Service
```bash
sudo systemctl restart postfix
```

### Reload Configuration
```bash
sudo postfix reload
```

### Clear Queue
```bash
sudo postsuper -d ALL
```

---

## 📱 Quick Fix Checklist

- [ ] Postfix service running: `systemctl status postfix`
- [ ] Gmail app password correct (16 chars, no spaces)
- [ ] SASL password file exists: `ls -la /etc/postfix/sasl_passwd*`
- [ ] No duplicate configs: `postfix check`
- [ ] Firewall allows port 587: `firewall-cmd --list-ports`
- [ ] TLS enabled: `postconf -n | grep tls`
- [ ] Can connect to Gmail: `telnet smtp.gmail.com 587`
- [ ] Queue is processing: `postqueue -p`

---

## 🆘 Emergency Commands

### Revert to Backup
```bash
sudo cp /etc/postfix/main.cf.backup /etc/postfix/main.cf
sudo systemctl restart postfix
```

### Complete Reset
```bash
# Backup current config
sudo cp /etc/postfix/main.cf /etc/postfix/main.cf.broken

# Install fresh config
sudo dnf reinstall postfix

# Rerun setup script
sudo bash setup-postfix.sh
```

### Get Help
```bash
# Show all config
postconf -n

# Show specific parameter
postconf smtp_tls_security_level

# Show default value
postconf -d smtp_tls_security_level
```

---

## 🚀 Optimasi Kecepatan Pengiriman Email (qmgr & pickup)

Untuk mempercepat proses pengiriman email, kamu bisa mengatur interval wakeup pada service `pickup` dan `qmgr` di `/etc/postfix/master.cf`.

### Langkah Optimasi:
1. Edit file `/etc/postfix/master.cf`:
   ```bash
   sudo nano /etc/postfix/master.cf
   ```
2. Cari baris yang mengandung `pickup` dan `qmgr`, misal:
   ```
   pickup   unix  n       -       n       60      1       pickup
   qmgr     unix  n       -       n       300     1       qmgr
   ```
3. Ubah kolom kelima (wakeup time) menjadi:
   - `pickup` → 5
   - `qmgr`   → 30
   Sehingga menjadi:
   ```
   pickup   unix  n       -       n       5       1       pickup
   qmgr     unix  n       -       n       30      1       qmgr
   ```
4. Simpan file dan keluar dari editor.
5. Restart Postfix:
   ```bash
   sudo systemctl restart postfix
   ```

### Penjelasan:
- **pickup**: Mengatur seberapa sering Postfix mengambil email baru dari maildrop (default 60 detik, disarankan 5 detik).
- **qmgr**: Mengatur seberapa sering queue manager memproses antrian email (default 300 detik, disarankan 30 detik).

Dengan pengaturan ini, email akan diproses dan dikirim lebih cepat dari servermu.