# 🚨 Disaster Recovery Playbook
## Prosedur Pemulihan Server — Cloud Backup & DR System

> **Dokumen ini adalah panduan operasional untuk memulihkan server yang mengalami kehancuran total (Total Data Loss).** Simpan dokumen ini di lokasi yang aman dan pastikan seluruh tim teknis memiliki akses.

---

## 📋 Daftar Isi

- [Skenario Bencana](#-skenario-bencana)
- [Pre-Requisites](#-pre-requisites)
- [Metode 1: One-Click Automated Recovery](#-metode-1-one-click-automated-recovery-rekomendasi)
- [Metode 2: Manual Step-by-Step Recovery](#-metode-2-manual-step-by-step-recovery)
- [Checklist Verifikasi Pasca-Restore](#-checklist-verifikasi-pasca-restore)
- [Estimasi Waktu Pemulihan (RTO)](#-estimasi-waktu-pemulihan-rto)
- [Troubleshooting](#-troubleshooting)

---

## 🔥 Skenario Bencana

Prosedur ini digunakan ketika terjadi salah satu (atau kombinasi) situasi berikut:

| # | Skenario | Dampak | Prioritas |
|---|----------|--------|-----------|
| 1 | **Database terhapus/corrupt** | Seluruh konten website hilang (user, post, transaksi) | 🔴 CRITICAL |
| 2 | **Server di-reset ulang** | OS bersih, semua data & konfigurasi lenyap | 🔴 CRITICAL |
| 3 | **Ransomware / Hacking** | File terenkripsi atau dimodifikasi oleh penyerang | 🔴 CRITICAL |
| 4 | **Disk failure / Hardware error** | Storage fisik rusak, data tidak bisa dibaca | 🔴 CRITICAL |
| 5 | **Human error** (salah hapus) | File atau database penting terhapus tidak sengaja | 🟡 HIGH |

---

## 📦 Pre-Requisites

Sebelum memulai prosedur pemulihan, pastikan VPS/server baru sudah memenuhi syarat:

```bash
# 1. OS terinstall (Ubuntu 20.04+ / Debian 11+ recommended)

# 2. Install paket dasar
sudo apt update && sudo apt install -y curl mysql-server apache2 tar gzip

# 3. Install Rclone
curl https://rclone.org/install.sh | sudo bash

# 4. Konfigurasi Rclone remote (gunakan konfigurasi yang sama)
rclone config
# → Buat remote bernama 'gdrive-backup' dengan kredensial Google Drive yang sama

# 5. Setup kredensial database
cat <<EOF > /root/.my.cnf
[client]
user=root
password="PASSWORD_DATABASE"
host=localhost

[mysqldump]
user=root
password="PASSWORD_DATABASE"
host=localhost
EOF
chmod 600 /root/.my.cnf
```

---

## ⚡ Metode 1: One-Click Automated Recovery (Rekomendasi)

> **Waktu estimasi: < 5 menit** | Direkomendasikan untuk pemulihan cepat.

Jika VPS baru sudah siap dengan Rclone terkonfigurasi, cukup **1 perintah**:

```bash
# Salin skrip restore ke server (jika belum ada)
scp scripts/restore.sh root@IP_SERVER_BARU:/root/scripts/restore.sh

# Atau download dari repository
curl -o /root/scripts/restore.sh https://raw.githubusercontent.com/USERNAME/REPO/main/scripts/restore.sh
chmod +x /root/scripts/restore.sh

# === EKSEKUSI ONE-CLICK RECOVERY ===
/bin/bash /root/scripts/restore.sh
```

### Apa yang dilakukan skrip ini secara otomatis?

```
┌─────────────────────────────────────────────────────────────────┐
│  🚑 AUTOMATED DISASTER RECOVERY ENGINE                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  STEP 1 → Scan & download backup terbaru dari Cloud Storage    │
│       ↓                                                         │
│  STEP 2 → Ekstraksi source code ke /var/www/html/              │
│       ↓                                                         │
│  STEP 3 → Import database SQL secara otomatis                  │
│       ↓                                                         │
│  STEP 4 → Set permission (www-data:www-data, 755/644)          │
│       ↓                                                         │
│  STEP 5 → Verifikasi HTTP 200 OK                              │
│       ↓                                                         │
│  STEP 6 → Kirim laporan pemulihan ke Telegram                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Restore file backup spesifik:

```bash
# Jika ingin me-restore dari file backup tertentu (bukan yang terbaru)
/bin/bash /root/scripts/restore.sh --file backup-production_db-2026-07-01_02-00-00.tar.gz
```

---

## 🔧 Metode 2: Manual Step-by-Step Recovery

> **Untuk audit & investigasi** — Gunakan metode ini jika perlu mengontrol setiap tahap secara manual.

### Step 1: Download Arsip Backup Terbaru

```bash
# Lihat daftar semua backup yang tersedia di cloud
rclone ls gdrive-backup:Server_Production_Backups

# Download backup terbaru ke direktori recovery
mkdir -p /root/recovery_temp
rclone copy "gdrive-backup:Server_Production_Backups" /root/recovery_temp/ \
    --include "backup-*.tar.gz" \
    --progress

# Verifikasi file sudah terunduh
ls -lah /root/recovery_temp/
```

### Step 2: Ekstraksi Source Code Website

```bash
# Identifikasi file backup terbaru
LATEST=$(ls -t /root/recovery_temp/backup-*.tar.gz | head -n1)
echo "File yang akan di-restore: ${LATEST}"

# Ekstraksi ke direktori web server
tar -zxvf "${LATEST}" -C /var/www/html/

# Verifikasi file terekstrak
ls -la /var/www/html/
```

### Step 3: Restore Database

```bash
# Temukan file SQL
SQL_FILE=$(find /var/www/html /root/recovery_temp -name "*.sql" | head -n1)
echo "File SQL: ${SQL_FILE}"

# Buat database jika belum ada
mysql --defaults-extra-file=/root/.my.cnf -e "CREATE DATABASE IF NOT EXISTS production_db;"

# Import database
mysql --defaults-extra-file=/root/.my.cnf production_db < "${SQL_FILE}"

# Hapus file SQL dari web directory (tidak perlu di-serve ke publik)
rm -f "${SQL_FILE}"

# Verifikasi database
mysql --defaults-extra-file=/root/.my.cnf -e "USE production_db; SHOW TABLES;"
```

### Step 4: Set Permission & Ownership

```bash
# Set ownership ke web server user
chown -R www-data:www-data /var/www/html/

# Set permission standar
find /var/www/html -type d -exec chmod 755 {} \;
find /var/www/html -type f -exec chmod 644 {} \;

# Restart web server
sudo systemctl restart apache2
# atau
sudo systemctl restart nginx
```

### Step 5: Verifikasi HTTP Endpoint

```bash
# Cek apakah website merespons
curl -I -s http://localhost | head -n 5

# Output yang diharapkan:
# HTTP/1.1 200 OK
# ...

# Test dari luar server (ganti IP_SERVER)
curl -I -s http://IP_SERVER | grep "HTTP/"
```

---

## ✅ Checklist Verifikasi Pasca-Restore

Setelah pemulihan, lakukan pengecekan menyeluruh:

| # | Item Verifikasi | Perintah | Expected |
|---|----------------|----------|----------|
| 1 | HTTP Response | `curl -I http://localhost` | `200 OK` |
| 2 | Database aktif | `mysql -e "SHOW DATABASES;"` | Database `production_db` ada |
| 3 | Tabel lengkap | `mysql production_db -e "SHOW TABLES;"` | Semua tabel ada |
| 4 | File web ada | `ls /var/www/html/index.*` | File index ditemukan |
| 5 | Permission benar | `stat -c '%U:%G' /var/www/html` | `www-data:www-data` |
| 6 | Web server running | `systemctl status apache2` | `active (running)` |
| 7 | SSL (jika ada) | `curl -I https://domain.com` | `200 OK` |
| 8 | DNS resolving | `dig domain.com` | IP yang benar |

---

## ⏱️ Estimasi Waktu Pemulihan (RTO)

| Tahap | Metode 1 (Otomatis) | Metode 2 (Manual) |
|-------|--------------------|--------------------|
| Download backup | ~1-3 menit | ~1-3 menit |
| Ekstraksi file | ~30 detik | ~1 menit |
| Import database | ~30 detik | ~2 menit |
| Set permission | ~10 detik | ~1 menit |
| Verifikasi | ~10 detik | ~2 menit |
| **TOTAL** | **~2-5 menit** | **~7-10 menit** |

> **Recovery Time Objective (RTO): < 10 menit**
> 
> **Recovery Point Objective (RPO): < 24 jam** (backup harian pukul 02:00 AM)

---

## 🔧 Troubleshooting

### Database import gagal
```bash
# Cek error log MySQL
sudo tail -50 /var/log/mysql/error.log

# Coba drop & recreate database
mysql --defaults-extra-file=/root/.my.cnf -e "DROP DATABASE production_db; CREATE DATABASE production_db;"
mysql --defaults-extra-file=/root/.my.cnf production_db < file_backup.sql
```

### Permission denied saat akses website
```bash
# Re-set ownership
sudo chown -R www-data:www-data /var/www/html/

# Cek SELinux (jika CentOS/RHEL)
sudo setenforce 0  # temporary
sudo setsebool -P httpd_read_user_content 1  # permanent
```

### Rclone tidak bisa connect
```bash
# Test koneksi
rclone lsd gdrive-backup:

# Jika token expired, re-authorize
rclone config reconnect gdrive-backup:

# Cek konfigurasi
rclone config show gdrive-backup
```

### Web server tidak start
```bash
# Cek status
sudo systemctl status apache2
sudo systemctl status nginx

# Cek port conflict
sudo netstat -tlnp | grep ':80'

# Restart
sudo systemctl restart apache2
```

---

> **Catatan Penting**: Simpan kredensial Rclone (Google Drive OAuth token) dan file `.my.cnf` di lokasi aman terpisah (misalnya password manager). Tanpa ini, prosedur recovery tidak dapat dijalankan.
