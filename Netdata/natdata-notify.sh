#!/bin/bash

# File ini disimpan di /opt/natdata-notify.sh
# Pastikan file executable: chmod +x /opt/natdata-notify.sh
# Jalankan via crontab setiap 1 menit, contoh crontab:
# * * * * * /opt/natdata-notify.sh
#
# Fungsi:
# - Mengirim email ALERT jika CPU ATAU RAM melebihi 85% (salah satu saja cukup)
# - Mengirim email RECOVERY jika kondisi kembali normal (keduanya di bawah 85%)
#
# Email hanya dikirim saat status berubah (dari normal ke alert, atau sebaliknya)

RECIPIENT="yourmail@yourdomain.com"
# Hitung pake docker exec, pastikan hasilnya cuma angka
CPU=$(docker exec netdata awk '{print $1 * 100}' /proc/loadavg)
RAM=$(docker exec netdata free | awk '/^Mem:/ {printf "%.1f", $3/$2 * 100.0}')

TH=85
STATE_FILE="/tmp/netdata.state"

# Load last state
if [ -f "$STATE_FILE" ]; then
  last=$(cat "$STATE_FILE")
else
  last="normal"
fi

# Tentuin status sekarang
now="normal"
# Pakai bc -l untuk floating compare
if [ "$(echo "$CPU > $TH" | bc -l)" -eq 1 ] || [ "$(echo "$RAM > $TH" | bc -l)" -eq 1 ]; then
  now="alert"
fi

# Kirim email kalau status berubah
if [ "$now" != "$last" ]; then
  if [ "$now" = "alert" ]; then
    SUBJECT="ALERT: CPU/RAM over threshold"
    BODY="CPU=${CPU}%, RAM=${RAM}% — over ${TH}%"
  else
    SUBJECT="RECOVERY: CPU/RAM back to normal"
    BODY="CPU=${CPU}%, RAM=${RAM}% — now under ${TH}%"
  fi

  echo "$BODY" | mail -s "$SUBJECT" "$RECIPIENT"
  echo "$now" > "$STATE_FILE"
fi