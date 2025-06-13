# Horizontal Scaling Demo Steps

> **Prerequisite:** Pastikan sudah ada Nginx yang berjalan di server (bukan container). Script dan stack ini TIDAK membuat container Nginx, melainkan menggunakan Nginx host sebagai load balancer. Config akan diupdate otomatis oleh Consul Template.

Dokumen ini menjelaskan langkah-langkah lengkap untuk mendemokan horizontal scaling pada aplikasi berbasis Docker, Nginx, dan Consul. Ikuti urutan berikut untuk setup, menjalankan, dan melakukan stress test pada sistem.

---

## 1. Jalankan Setup Script

Jalankan script setup untuk menyiapkan seluruh infrastruktur (hanya perlu sekali, sebagai root):
```bash
sudo bash setup-scaling.sh
```
Script ini akan:
- Membuat struktur direktori dan file konfigurasi
- Generate Docker Compose, Consul Template, dan aplikasi fallback/stress
- Membuat systemd service untuk auto-scaling
- Install dependensi (docker-compose, bc, dsb)

---

## 2. Jalankan Docker Compose

Masuk ke direktori scaling dan jalankan semua container:
```bash
cd /opt/scaling
sudo docker-compose up -d
```
Container yang akan berjalan:
- Consul (service discovery, port 8500)
- Consul Template (sinkronisasi config Nginx)
- Nginx (load balancer, port 80)
- Fallback app (backup server, port 8081)
- Web app (web-app-1, port 5000)

---

## 3. Aktifkan Monitoring & Auto-Scaling

Aktifkan service monitoring untuk scaling otomatis:
```bash
sudo systemctl enable scaling-monitor.service
sudo systemctl start scaling-monitor.service
```
Service ini akan:
- Memantau resource (CPU/RAM) semua container web-app
- Menambah container jika rata-rata CPU/RAM > 85%
- Mengurangi container jika rata-rata CPU/RAM < 30% (dan jumlah > 1)
- Register/deregister container ke Consul
- Log ke /opt/scaling/logs/scaling.log

---

## 4. Testing & Stress Test

### Akses Aplikasi
- Akses aplikasi melalui Nginx load balancer:
  - http://localhost:5000
- Akses fallback app (jika semua web-app down):
  - http://localhost:8081/

### Lakukan Stress Test
- Buka endpoint `/stress` untuk memicu beban CPU & RAM pada salah satu container:
  - http://localhost:5000/stress
- Pantau scaling otomatis di log:
  - tail -f /opt/scaling/logs/scaling.log
- Cek jumlah container web-app yang aktif:
  - sudo docker ps | grep web-app

---

## 5. Monitoring & Konsul GUI

- Konsul UI dapat diakses di:
  - http://localhost:8500
- Di sini, Anda bisa melihat service discovery, health check, dan status semua web-app yang terdaftar.

---

## 6. Tips & Troubleshooting

- Untuk restart seluruh stack:
  ```bash
  sudo docker-compose down
  sudo docker-compose up -d
  sudo systemctl restart scaling-monitor.service
  ```
- Untuk menghapus semua container web-app:
  ```bash
  sudo docker rm -f $(docker ps -aq --filter "name=web-app-")
  ```
- Jika scaling tidak berjalan, cek log di `/opt/scaling/logs/scaling.log` dan pastikan service `scaling-monitor.service` aktif.

---

## 7. Ringkasan Alur Demo
1. Jalankan setup script
2. Jalankan docker-compose
3. Aktifkan monitoring
4. Akses aplikasi via Nginx (port 80)
5. Lakukan stress test (endpoint /stress)
6. Lihat scaling otomatis (docker ps, log, dan Consul UI port 8500)

---

Selamat mendemokan horizontal scaling!
