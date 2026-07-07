#!/bin/bash

# ==============================================================================
#  AUTOMATED CLOUD BACKUP ENGINE — Production Grade
# ==============================================================================
#  Deskripsi : Skrip automasi backup database & source code web server.
#              Upload ke remote cloud storage via Rclone, implementasi
#              retention policy, dan notifikasi status real-time via Telegram.
#
#  Author    : SysAdmin
#  Lokasi    : /root/scripts/backup.sh
#  Izin      : chmod +x /root/scripts/backup.sh
#
#  Fitur Keamanan:
#    - Zero-Plaintext Password (menggunakan .my.cnf)
#    - Concurrency Control via flock (diatur di cronjob)
#    - Pengecekan pre-flight sebelum eksekusi
#    - Error handling & alerting di setiap tahap kritis
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION & METRICS
# ==============================================================================
DATE=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_DIR="/root/backup_temp"
WEB_DIR="/var/www/html"
DB_NAME="production_db"
BACKUP_NAME="backup-${DB_NAME}-${DATE}.tar.gz"
MY_CNF="/root/.my.cnf"

# Rclone Remote Configuration
# Sesuaikan dengan nama remote yang sudah dikonfigurasi via 'rclone config'
RCLONE_REMOTE="gdrive-backup"
RCLONE_FOLDER="Server_Production_Backups"

# Telegram Bot Alerting Configuration
# Dapatkan token dari @BotFather dan chat_id dari @userinfobot di Telegram
TELEGRAM_BOT_TOKEN="YOUR_BOT_TOKEN_HERE"
TELEGRAM_CHAT_ID="YOUR_CHAT_ID_HERE"

# Retention Policy (dalam hari)
RETENTION_DAYS=7

# Benchmarking & Host Info
START_TIME=$(date +%s)
HOSTNAME=$(hostname)
IP_ADDRESS=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "N/A")

# ==============================================================================
# FUNGSI: Kirim Notifikasi Telegram
# ==============================================================================
send_telegram() {
    local MESSAGE="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
         -d "chat_id=${TELEGRAM_CHAT_ID}" \
         -d "text=${MESSAGE}" \
         -d "parse_mode=Markdown" > /dev/null 2>&1
}

# ==============================================================================
# FUNGSI: Kirim Alert Gagal & Exit
# ==============================================================================
send_failure_alert() {
    local STEP="$1"
    local DETAIL="$2"
    local TEXT="*🔴 CLOUD BACKUP FAILED ALERT*%0A%0A"
    TEXT="${TEXT}🖥️ Server: \`${HOSTNAME}\` (${IP_ADDRESS})%0A"
    TEXT="${TEXT}📅 Waktu: $(date +"%Y-%m-%d %H:%M:%S WIB")%0A"
    TEXT="${TEXT}❌ Tahap Gagal: ${STEP}%0A"
    TEXT="${TEXT}📝 Detail: ${DETAIL}"
    send_telegram "${TEXT}"
    echo "[$(date)] ❌ BACKUP GAGAL pada tahap: ${STEP} — ${DETAIL}"
    exit 1
}

# ==============================================================================
# PRE-FLIGHT CHECKS & DIRECTORY SETUP
# ==============================================================================
echo "=================================================================="
echo "[$(date)] --- MEMULAI PROSES AUTOMATED BACKUP ---"
echo "=================================================================="

# Buat direktori backup jika belum ada
mkdir -p "${BACKUP_DIR}"

# Cek file kredensial .my.cnf
if [ ! -f "${MY_CNF}" ]; then
    send_failure_alert "Pre-Flight Check" "File kredensial ${MY_CNF} tidak ditemukan! Buat file ini terlebih dahulu."
fi

# Cek apakah rclone terinstall
if ! command -v rclone &> /dev/null; then
    send_failure_alert "Pre-Flight Check" "Rclone tidak terinstall. Jalankan: curl https://rclone.org/install.sh | sudo bash"
fi

# Cek apakah mysqldump tersedia
if ! command -v mysqldump &> /dev/null; then
    send_failure_alert "Pre-Flight Check" "mysqldump tidak ditemukan. Install: apt install mysql-client"
fi

# Cek apakah direktori web ada
if [ ! -d "${WEB_DIR}" ]; then
    send_failure_alert "Pre-Flight Check" "Direktori web ${WEB_DIR} tidak ditemukan!"
fi

echo "[$(date)] ✅ Pre-flight checks passed. Semua dependensi tersedia."

# ==============================================================================
# STEP 1: EKSTRAKSI & KOMPRESI DATA (WITH ZERO-PLAINTEXT AUTH)
# ==============================================================================
echo "[$(date)] 📦 STEP 1: Mengekspor Database '${DB_NAME}' menggunakan kredensial aman (.my.cnf)..."

mysqldump --defaults-extra-file="${MY_CNF}" \
          --single-transaction \
          --quick \
          --lock-tables=false \
          --routines \
          --triggers \
          --events \
          "${DB_NAME}" > "${BACKUP_DIR}/${DB_NAME}-${DATE}.sql"

if [ $? -ne 0 ]; then
    send_failure_alert "Database Export" "Gagal mengekspor database \`${DB_NAME}\`. Periksa koneksi atau izin database."
fi

SQL_SIZE=$(du -sh "${BACKUP_DIR}/${DB_NAME}-${DATE}.sql" | cut -f1)
echo "[$(date)] ✅ Database berhasil diekspor. Ukuran SQL: ${SQL_SIZE}"

echo "[$(date)] 📦 STEP 1b: Mengompresi Source Code & File SQL menjadi tarball..."

tar -czf "${BACKUP_DIR}/${BACKUP_NAME}" \
    -C "${WEB_DIR}" . \
    -C "${BACKUP_DIR}" "${DB_NAME}-${DATE}.sql"

if [ $? -ne 0 ]; then
    send_failure_alert "Kompresi Tarball" "Gagal membuat arsip \`${BACKUP_NAME}\`."
fi

# Hapus file SQL mentah segera setelah diarsipkan (hemat disk)
rm -f "${BACKUP_DIR}/${DB_NAME}-${DATE}.sql"

ARCHIVE_SIZE=$(du -sh "${BACKUP_DIR}/${BACKUP_NAME}" | cut -f1)
echo "[$(date)] ✅ Arsip tarball berhasil dibuat: ${BACKUP_NAME} (${ARCHIVE_SIZE})"

# ==============================================================================
# STEP 2: REPLIKASI OFFSITE (RCLONE CLOUD UPLOAD)
# ==============================================================================
echo "[$(date)] ☁️  STEP 2: Mengunggah arsip ke Cloud Storage via Rclone..."

rclone copy "${BACKUP_DIR}/${BACKUP_NAME}" \
            "${RCLONE_REMOTE}:${RCLONE_FOLDER}" \
            --progress \
            --transfers 4 \
            --checkers 8 \
            --retries 3 \
            --low-level-retries 10

if [ $? -ne 0 ]; then
    send_failure_alert "Cloud Upload" "Gagal mengunggah \`${BACKUP_NAME}\` ke \`${RCLONE_REMOTE}:${RCLONE_FOLDER}\`."
fi

echo "[$(date)] ✅ Upload ke cloud storage berhasil."

# ==============================================================================
# STEP 3: IMPLEMENTASI RETENTION POLICY (HAPUS DATA > RETENTION_DAYS)
# ==============================================================================
echo "[$(date)] 🧹 STEP 3: Menjalankan Retention Policy Engine (Purge > ${RETENTION_DAYS} hari)..."

# Pembersihan lokal VPS
LOCAL_DELETED=$(find "${BACKUP_DIR}" -type f -name "backup-*.tar.gz" -mtime +${RETENTION_DAYS} -print -delete | wc -l)
echo "[$(date)]    → File lokal dihapus: ${LOCAL_DELETED} file"

# Pembersihan remote Cloud Storage
rclone delete "${RCLONE_REMOTE}:${RCLONE_FOLDER}" --min-age "${RETENTION_DAYS}d" --rmdirs 2>/dev/null
echo "[$(date)]    → Pembersihan remote cloud selesai."

echo "[$(date)] ✅ Retention policy berhasil dieksekusi."

# ==============================================================================
# STEP 4: MONITORING METRIK & NOTIFIKASI TELEGRAM REAL-TIME
# ==============================================================================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
FILE_SIZE=$(du -sh "${BACKUP_DIR}/${BACKUP_NAME}" 2>/dev/null | cut -f1 || echo "N/A")
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}')
DISK_AVAILABLE=$(df -h / | awk 'NR==2 {print $4}')
TOTAL_BACKUPS=$(find "${BACKUP_DIR}" -type f -name "backup-*.tar.gz" | wc -l)
STATUS="🟢 SUCCESS"

# Format durasi ke format yang lebih readable
if [ ${DURATION} -ge 60 ]; then
    DURATION_FMT="$((DURATION / 60)) menit $((DURATION % 60)) detik"
else
    DURATION_FMT="${DURATION} detik"
fi

TEXT="*☁️ CLOUD BACKUP STATUS REPORT*%0A"
TEXT="${TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━%0A%0A"
TEXT="${TEXT}${STATUS}%0A%0A"
TEXT="${TEXT}🖥️ Server: \`${HOSTNAME}\` (${IP_ADDRESS})%0A"
TEXT="${TEXT}📅 Waktu: $(date +"%Y-%m-%d %H:%M:%S WIB")%0A"
TEXT="${TEXT}📦 File: \`${BACKUP_NAME}\`%0A"
TEXT="${TEXT}⚖️ Ukuran: ${FILE_SIZE}%0A"
TEXT="${TEXT}⏳ Durasi: ${DURATION_FMT}%0A"
TEXT="${TEXT}💾 Disk Terpakai: ${DISK_USAGE} (Sisa: ${DISK_AVAILABLE})%0A"
TEXT="${TEXT}🗂️ Total Backup Lokal: ${TOTAL_BACKUPS} file%0A"
TEXT="${TEXT}🧹 Retention: ${RETENTION_DAYS} hari (${LOCAL_DELETED} file lama dihapus)%0A%0A"
TEXT="${TEXT}_Sistem berjalan otomatis tanpa interaksi manusia._"

send_telegram "${TEXT}"

echo "=================================================================="
echo "[$(date)] --- PROSES AUTOMATED BACKUP BERHASIL DISELESAIKAN ---"
echo "[$(date)] 📊 Ringkasan:"
echo "             File   : ${BACKUP_NAME}"
echo "             Ukuran : ${FILE_SIZE}"
echo "             Durasi : ${DURATION_FMT}"
echo "             Disk   : ${DISK_USAGE} terpakai (${DISK_AVAILABLE} tersisa)"
echo "=================================================================="
