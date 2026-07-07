#!/bin/bash

# ==============================================================================
#  AUTOMATED DISASTER RECOVERY — One-Click Restore Engine
# ==============================================================================
#  Deskripsi : Skrip pemulihan otomatis untuk mengembalikan web server dari
#              backup terbaru di cloud storage. Satu perintah untuk memulihkan
#              seluruh website + database dalam waktu < 5 menit.
#
#  Author    : SysAdmin
#  Lokasi    : /root/scripts/restore.sh
#  Izin      : chmod +x /root/scripts/restore.sh
#
#  Penggunaan:
#    /bin/bash /root/scripts/restore.sh
#    /bin/bash /root/scripts/restore.sh --file backup-production_db-2026-07-05.tar.gz
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================
RESTORE_DIR="/root/recovery_temp"
WEB_DIR="/var/www/html"
DB_NAME="production_db"
MY_CNF="/root/.my.cnf"
RCLONE_REMOTE="gdrive-backup"
RCLONE_FOLDER="Server_Production_Backups"

# Telegram Bot Alerting Configuration
TELEGRAM_BOT_TOKEN="YOUR_BOT_TOKEN_HERE"
TELEGRAM_CHAT_ID="YOUR_CHAT_ID_HERE"

# Benchmarking
START_TIME=$(date +%s)
HOSTNAME=$(hostname)

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
# FUNGSI: Tampilkan Banner
# ==============================================================================
show_banner() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║       🚨 AUTOMATED DISASTER RECOVERY ENGINE 🚨             ║"
    echo "║       One-Click Server Restoration System                   ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
}

# ==============================================================================
# PARSE ARGUMEN (opsional: --file <nama_file>)
# ==============================================================================
SPECIFIC_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --file)
            SPECIFIC_FILE="$2"
            shift 2
            ;;
        --help)
            echo "Penggunaan: $0 [--file <nama_backup.tar.gz>]"
            echo ""
            echo "Opsi:"
            echo "  --file    Tentukan file backup spesifik untuk di-restore"
            echo "            Jika tidak ditentukan, akan mengambil backup terbaru"
            echo ""
            exit 0
            ;;
        *)
            echo "❌ Argumen tidak dikenal: $1"
            echo "Gunakan --help untuk melihat opsi."
            exit 1
            ;;
    esac
done

# ==============================================================================
# PRE-FLIGHT CHECKS
# ==============================================================================
show_banner
echo "[$(date)] 🚨 DISASTER RECOVERY — Memulai prosedur pemulihan otomatis..."
echo ""

# Cek dependensi
for CMD in rclone mysql curl tar; do
    if ! command -v ${CMD} &> /dev/null; then
        echo "❌ ERROR: Perintah '${CMD}' tidak ditemukan. Install terlebih dahulu."
        exit 1
    fi
done

# Cek file kredensial
if [ ! -f "${MY_CNF}" ]; then
    echo "❌ ERROR FATAL: File kredensial ${MY_CNF} tidak ditemukan!"
    echo "   Buat file ini dengan perintah:"
    echo "   cat <<EOF > /root/.my.cnf"
    echo "   [client]"
    echo "   user=root"
    echo "   password=\"PASSWORD_ANDA\""
    echo "   host=localhost"
    echo "   EOF"
    echo "   chmod 600 /root/.my.cnf"
    exit 1
fi

# Buat direktori recovery
mkdir -p "${RESTORE_DIR}"

echo "[$(date)] ✅ Pre-flight checks passed."
echo ""

# ==============================================================================
# STEP 1: UNDUH FILE BACKUP DARI CLOUD STORAGE
# ==============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⬇️  STEP 1: Mengunduh arsip backup dari Cloud Storage..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -n "${SPECIFIC_FILE}" ]; then
    LATEST_BACKUP="${SPECIFIC_FILE}"
    echo "📌 Menggunakan file spesifik: ${LATEST_BACKUP}"
else
    echo "🔍 Mencari file backup terbaru di remote storage..."
    LATEST_BACKUP=$(rclone lsf "${RCLONE_REMOTE}:${RCLONE_FOLDER}" --files-only | sort -r | head -n 1)
fi

if [ -z "${LATEST_BACKUP}" ]; then
    echo "❌ ERROR: Tidak menemukan file backup di remote storage!"
    echo "   Pastikan remote '${RCLONE_REMOTE}:${RCLONE_FOLDER}' berisi file backup."
    send_telegram "*🔴 DISASTER RECOVERY GAGAL*%0A%0AFile backup tidak ditemukan di cloud storage."
    exit 1
fi

echo "📦 File backup target: ${LATEST_BACKUP}"
echo "⬇️  Mengunduh dari ${RCLONE_REMOTE}:${RCLONE_FOLDER}/${LATEST_BACKUP}..."

rclone copy "${RCLONE_REMOTE}:${RCLONE_FOLDER}/${LATEST_BACKUP}" "${RESTORE_DIR}/" \
            --progress \
            --transfers 4 \
            --retries 3

if [ ! -f "${RESTORE_DIR}/${LATEST_BACKUP}" ]; then
    echo "❌ ERROR: File gagal diunduh!"
    send_telegram "*🔴 DISASTER RECOVERY GAGAL*%0A%0AGagal mengunduh file backup dari cloud."
    exit 1
fi

DL_SIZE=$(du -sh "${RESTORE_DIR}/${LATEST_BACKUP}" | cut -f1)
echo "[$(date)] ✅ Download selesai. Ukuran file: ${DL_SIZE}"
echo ""

# ==============================================================================
# STEP 2: EKSTRAKSI SOURCE CODE KE FOLDER WEB SERVER
# ==============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📂 STEP 2: Mengekstrak file website ke ${WEB_DIR}..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Buat backup dari state website saat ini (safety net)
if [ -d "${WEB_DIR}" ] && [ "$(ls -A ${WEB_DIR} 2>/dev/null)" ]; then
    echo "🛡️  Membuat snapshot web directory saat ini sebagai safety net..."
    SAFETY_BACKUP="/root/pre_restore_snapshot_$(date +%Y%m%d_%H%M%S).tar.gz"
    tar -czf "${SAFETY_BACKUP}" -C "${WEB_DIR}" . 2>/dev/null || true
    echo "    → Snapshot tersimpan di: ${SAFETY_BACKUP}"
fi

# Buat direktori web jika belum ada
mkdir -p "${WEB_DIR}"

# Ekstraksi
tar -zxvf "${RESTORE_DIR}/${LATEST_BACKUP}" -C "${WEB_DIR}/" 2>&1 | tail -5
echo "[$(date)] ✅ Ekstraksi file website selesai."
echo ""

# ==============================================================================
# STEP 3: RESTORASI DATABASE SQL
# ==============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🗄️  STEP 3: Mengimpor kembali database..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Cari file SQL di dalam arsip yang sudah diekstrak
SQL_FILE=$(find "${WEB_DIR}" "${RESTORE_DIR}" -maxdepth 2 -name "*.sql" -type f 2>/dev/null | head -n 1)

if [ -n "${SQL_FILE}" ] && [ -f "${SQL_FILE}" ]; then
    SQL_SIZE=$(du -sh "${SQL_FILE}" | cut -f1)
    echo "📄 File SQL ditemukan: $(basename "${SQL_FILE}") (${SQL_SIZE})"

    # Buat database jika belum ada
    mysql --defaults-extra-file="${MY_CNF}" -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;" 2>/dev/null

    # Import database
    echo "🔄 Mengimpor database ke '${DB_NAME}'..."
    mysql --defaults-extra-file="${MY_CNF}" "${DB_NAME}" < "${SQL_FILE}"

    if [ $? -eq 0 ]; then
        echo "[$(date)] ✅ Database '${DB_NAME}' berhasil dipulihkan dari: $(basename "${SQL_FILE}")"
        # Hapus file SQL dari web directory (tidak perlu di-serve)
        rm -f "${SQL_FILE}"
    else
        echo "⚠️  WARNING: Import database mungkin memiliki error. Periksa secara manual."
    fi
else
    echo "⚠️  Peringatan: File .sql tidak ditemukan di dalam arsip!"
    echo "   Database mungkin perlu di-restore secara manual."
fi

echo ""

# ==============================================================================
# STEP 4: SET PERMISSIONS & CLEANUP
# ==============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 STEP 4: Mengatur izin file & pembersihan..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Set ownership ke web server user
chown -R www-data:www-data "${WEB_DIR}"
echo "✅ Ownership diatur ke www-data:www-data"

# Set permission standar
find "${WEB_DIR}" -type d -exec chmod 755 {} \;
find "${WEB_DIR}" -type f -exec chmod 644 {} \;
echo "✅ Permission file/folder diatur (755/644)"

# Cleanup temp
rm -rf "${RESTORE_DIR}"
echo "✅ Direktori temporary dibersihkan."

echo ""

# ==============================================================================
# STEP 5: VERIFIKASI HTTP ENDPOINT
# ==============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌐 STEP 5: Verifikasi integritas HTTP endpoint..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Tunggu sebentar agar web server merespon
sleep 2

HTTP_RESPONSE=$(curl -I -s -o /dev/null -w "%{http_code}" http://localhost 2>/dev/null || echo "000")
HTTP_HEADER=$(curl -I -s http://localhost 2>/dev/null | head -n 1 || echo "Connection refused")

if [ "${HTTP_RESPONSE}" = "200" ]; then
    echo "✅ HTTP Status: ${HTTP_HEADER}"
    echo "🎉 Website kembali ONLINE dan merespons normal!"
    RESTORE_STATUS="🟢 SUCCESS"
elif [ "${HTTP_RESPONSE}" = "000" ]; then
    echo "⚠️  HTTP Status: Web server tidak merespons."
    echo "   Kemungkinan web server (Apache/Nginx) perlu di-restart:"
    echo "   → sudo systemctl restart apache2"
    echo "   → sudo systemctl restart nginx"
    RESTORE_STATUS="🟡 PARTIAL (web server perlu restart)"
else
    echo "⚠️  HTTP Status: ${HTTP_HEADER} (Code: ${HTTP_RESPONSE})"
    echo "   Website merespons tapi dengan status non-200. Periksa konfigurasi."
    RESTORE_STATUS="🟡 PARTIAL (HTTP ${HTTP_RESPONSE})"
fi

echo ""

# ==============================================================================
# STEP 6: LAPORAN FINAL & NOTIFIKASI
# ==============================================================================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

if [ ${DURATION} -ge 60 ]; then
    DURATION_FMT="$((DURATION / 60)) menit $((DURATION % 60)) detik"
else
    DURATION_FMT="${DURATION} detik"
fi

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           🎉 DISASTER RECOVERY REPORT                      ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Status    : ${RESTORE_STATUS}"
echo "║  Server    : ${HOSTNAME}"
echo "║  File      : ${LATEST_BACKUP}"
echo "║  Ukuran    : ${DL_SIZE}"
echo "║  Durasi    : ${DURATION_FMT}"
echo "║  HTTP      : ${HTTP_RESPONSE}"
echo "╚══════════════════════════════════════════════════════════════╝"

# Kirim notifikasi Telegram
TEXT="*🚑 DISASTER RECOVERY REPORT*%0A"
TEXT="${TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━%0A%0A"
TEXT="${TEXT}Status: ${RESTORE_STATUS}%0A%0A"
TEXT="${TEXT}🖥️ Server: \`${HOSTNAME}\`%0A"
TEXT="${TEXT}📅 Waktu: $(date +"%Y-%m-%d %H:%M:%S WIB")%0A"
TEXT="${TEXT}📦 File: \`${LATEST_BACKUP}\`%0A"
TEXT="${TEXT}⚖️ Ukuran: ${DL_SIZE}%0A"
TEXT="${TEXT}⏳ Durasi: ${DURATION_FMT}%0A"
TEXT="${TEXT}🌐 HTTP: ${HTTP_RESPONSE}%0A%0A"
TEXT="${TEXT}_Server telah dipulihkan secara otomatis._"

send_telegram "${TEXT}"

echo ""
echo "[$(date)] 🏁 Prosedur Disaster Recovery selesai."
