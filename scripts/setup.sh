#!/bin/bash

# ==============================================================================
#  SETUP & DEPLOYMENT SCRIPT — Cloud Backup & DR System
# ==============================================================================
#  Deskripsi : Skrip inisialisasi untuk men-deploy seluruh sistem automasi
#              Cloud Backup & Disaster Recovery di server Linux baru.
#              Menginstall dependensi, mengkonfigurasi kredensial, cronjob,
#              dan logrotate secara otomatis.
#
#  Author    : SysAdmin
#  Penggunaan: sudo bash setup.sh
# ==============================================================================

set -euo pipefail

# ==============================================================================
# WARNA OUTPUT
# ==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ==============================================================================
# VARIABEL KONFIGURASI
# ==============================================================================
SCRIPTS_DIR="/root/scripts"
BACKUP_DIR="/root/backup_temp"
LOG_FILE="/var/log/backup.log"
LOCK_FILE="/var/lock/auto_backup.lock"
MY_CNF="/root/.my.cnf"
LOGROTATE_CONF="/etc/logrotate.d/auto_backup"

# ==============================================================================
# FUNGSI UTILITAS
# ==============================================================================
print_header() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     ☁️  Cloud Backup & Disaster Recovery — Setup Wizard     ║${NC}"
    echo -e "${CYAN}║              Production Environment Deployment               ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

log_info()    { echo -e "${BLUE}[INFO]${NC}    $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $1"; }

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "Skrip ini harus dijalankan sebagai root (sudo)!"
        exit 1
    fi
}

# ==============================================================================
# STEP 1: CEK & INSTALL DEPENDENSI
# ==============================================================================
install_dependencies() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  📦 STEP 1: Memeriksa & Menginstall Dependensi${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Update package list
    log_info "Mengupdate daftar paket..."
    apt-get update -qq > /dev/null 2>&1

    # Daftar paket yang dibutuhkan
    PACKAGES=("curl" "mysql-client" "tar" "gzip" "logrotate" "cron")

    for PKG in "${PACKAGES[@]}"; do
        if dpkg -s "${PKG}" &> /dev/null; then
            log_success "${PKG} sudah terinstall."
        else
            log_info "Menginstall ${PKG}..."
            apt-get install -y -qq "${PKG}" > /dev/null 2>&1
            log_success "${PKG} berhasil diinstall."
        fi
    done

    # Install rclone (cara resmi)
    if command -v rclone &> /dev/null; then
        RCLONE_VERSION=$(rclone version | head -n1)
        log_success "Rclone sudah terinstall: ${RCLONE_VERSION}"
    else
        log_info "Menginstall Rclone..."
        curl -s https://rclone.org/install.sh | bash > /dev/null 2>&1
        if command -v rclone &> /dev/null; then
            log_success "Rclone berhasil diinstall: $(rclone version | head -n1)"
        else
            log_error "Gagal menginstall Rclone. Install manual: https://rclone.org/install/"
        fi
    fi
}

# ==============================================================================
# STEP 2: BUAT STRUKTUR DIREKTORI
# ==============================================================================
setup_directories() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  📂 STEP 2: Membuat Struktur Direktori${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    mkdir -p "${SCRIPTS_DIR}"
    mkdir -p "${BACKUP_DIR}"
    touch "${LOG_FILE}"
    chmod 644 "${LOG_FILE}"

    log_success "Direktori skrip     : ${SCRIPTS_DIR}"
    log_success "Direktori backup    : ${BACKUP_DIR}"
    log_success "File log            : ${LOG_FILE}"
}

# ==============================================================================
# STEP 3: DEPLOY SKRIP BACKUP & RESTORE
# ==============================================================================
deploy_scripts() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  🚀 STEP 3: Men-deploy Skrip Automasi${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Cek apakah file skrip ada di direktori repository saat ini
    REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

    if [ -f "${REPO_DIR}/backup.sh" ]; then
        cp "${REPO_DIR}/backup.sh" "${SCRIPTS_DIR}/backup.sh"
        chmod +x "${SCRIPTS_DIR}/backup.sh"
        log_success "backup.sh di-deploy ke ${SCRIPTS_DIR}/backup.sh"
    else
        log_warning "backup.sh tidak ditemukan di ${REPO_DIR}. Salin manual ke ${SCRIPTS_DIR}/"
    fi

    if [ -f "${REPO_DIR}/restore.sh" ]; then
        cp "${REPO_DIR}/restore.sh" "${SCRIPTS_DIR}/restore.sh"
        chmod +x "${SCRIPTS_DIR}/restore.sh"
        log_success "restore.sh di-deploy ke ${SCRIPTS_DIR}/restore.sh"
    else
        log_warning "restore.sh tidak ditemukan di ${REPO_DIR}. Salin manual ke ${SCRIPTS_DIR}/"
    fi
}

# ==============================================================================
# STEP 4: KONFIGURASI KREDENSIAL DATABASE (.my.cnf)
# ==============================================================================
setup_credentials() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  🔐 STEP 4: Konfigurasi Kredensial Database (Zero-Plaintext)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if [ -f "${MY_CNF}" ]; then
        log_success "File ${MY_CNF} sudah ada. Melewati pembuatan."
        log_info "Memastikan permission sudah benar..."
        chmod 600 "${MY_CNF}"
        log_success "Permission diset ke 600 (hanya root yang bisa baca)."
    else
        log_info "Membuat file kredensial database..."
        echo ""
        read -p "    Masukkan username database [root]: " DB_USER
        DB_USER=${DB_USER:-root}
        read -sp "    Masukkan password database: " DB_PASS
        echo ""
        read -p "    Masukkan host database [localhost]: " DB_HOST
        DB_HOST=${DB_HOST:-localhost}

        cat <<EOF > "${MY_CNF}"
[client]
user=${DB_USER}
password="${DB_PASS}"
host=${DB_HOST}

[mysqldump]
user=${DB_USER}
password="${DB_PASS}"
host=${DB_HOST}
EOF

        chmod 600 "${MY_CNF}"
        log_success "File kredensial dibuat di ${MY_CNF} dengan permission 600."
        log_info "Password TIDAK akan pernah muncul di ps aux atau log."
    fi
}

# ==============================================================================
# STEP 5: KONFIGURASI RCLONE REMOTE
# ==============================================================================
setup_rclone() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  ☁️  STEP 5: Konfigurasi Rclone Remote Storage${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Cek apakah remote sudah dikonfigurasi
    if rclone listremotes 2>/dev/null | grep -q "gdrive-backup:"; then
        log_success "Remote 'gdrive-backup' sudah dikonfigurasi."
        log_info "Menguji koneksi ke remote..."
        if rclone lsd "gdrive-backup:" > /dev/null 2>&1; then
            log_success "Koneksi ke remote berhasil!"
        else
            log_warning "Koneksi gagal. Jalankan 'rclone config' untuk mengkonfigurasi ulang."
        fi
    else
        log_warning "Remote 'gdrive-backup' belum dikonfigurasi."
        echo ""
        echo "  Untuk mengkonfigurasi Rclone, jalankan perintah berikut:"
        echo ""
        echo -e "  ${YELLOW}rclone config${NC}"
        echo ""
        echo "  Pilih opsi:"
        echo "    → n (New remote)"
        echo "    → Nama: gdrive-backup"
        echo "    → Tipe: Google Drive (pilih nomor yang sesuai)"
        echo "    → Ikuti instruksi autentikasi OAuth"
        echo ""
        read -p "  Apakah Anda ingin menjalankan 'rclone config' sekarang? [y/N]: " RCLONE_SETUP
        if [[ "${RCLONE_SETUP}" =~ ^[Yy]$ ]]; then
            rclone config
        fi
    fi
}

# ==============================================================================
# STEP 6: SETUP CRONJOB DENGAN FLOCK PROTECTION
# ==============================================================================
setup_cronjob() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  ⏰ STEP 6: Konfigurasi Cronjob (Anti-Crash/flock)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    CRON_ENTRY="0 2 * * * /usr/bin/flock -n ${LOCK_FILE} /bin/bash ${SCRIPTS_DIR}/backup.sh >> ${LOG_FILE} 2>&1"

    # Cek apakah cronjob sudah ada
    if crontab -l 2>/dev/null | grep -q "backup.sh"; then
        log_success "Cronjob backup sudah terdaftar."
        log_info "Entry saat ini:"
        crontab -l 2>/dev/null | grep "backup.sh" | while read -r line; do
            echo "    ${line}"
        done
    else
        log_info "Mendaftarkan cronjob baru..."
        (crontab -l 2>/dev/null; echo "${CRON_ENTRY}") | crontab -
        log_success "Cronjob berhasil didaftarkan:"
        echo "    ${CRON_ENTRY}"
        echo ""
        log_info "Backup akan berjalan otomatis setiap hari pukul 02:00 AM."
        log_info "Proteksi flock aktif: mencegah eksekusi ganda jika backup sebelumnya belum selesai."
    fi
}

# ==============================================================================
# STEP 7: DEPLOY KONFIGURASI LOGROTATE
# ==============================================================================
setup_logrotate() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  📋 STEP 7: Deploy Konfigurasi Logrotate${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    cat <<'EOF' > "${LOGROTATE_CONF}"
/var/log/backup.log {
    monthly
    rotate 6
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF

    log_success "Konfigurasi logrotate di-deploy ke ${LOGROTATE_CONF}"
    log_info "Log akan dirotasi bulanan, dikompres, dan hanya menyimpan 6 bulan riwayat."
}

# ==============================================================================
# STEP 8: VALIDASI FINAL
# ==============================================================================
final_validation() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  ✅ STEP 8: Validasi Final${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    PASS=0
    FAIL=0

    # Cek setiap komponen
    checks=(
        "command -v rclone:Rclone terinstall"
        "command -v mysqldump:mysqldump tersedia"
        "command -v curl:curl tersedia"
        "test -f ${SCRIPTS_DIR}/backup.sh:backup.sh deployed"
        "test -f ${SCRIPTS_DIR}/restore.sh:restore.sh deployed"
        "test -f ${MY_CNF}:Kredensial .my.cnf ada"
        "test -f ${LOGROTATE_CONF}:Logrotate terkonfigurasi"
        "crontab -l 2>/dev/null | grep -q backup.sh:Cronjob terdaftar"
    )

    for check in "${checks[@]}"; do
        CMD="${check%%:*}"
        DESC="${check##*:}"
        if eval "${CMD}" > /dev/null 2>&1; then
            echo -e "    ${GREEN}✅${NC} ${DESC}"
            ((PASS++))
        else
            echo -e "    ${RED}❌${NC} ${DESC}"
            ((FAIL++))
        fi
    done

    echo ""
    echo -e "    Hasil: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"

    if [ ${FAIL} -eq 0 ]; then
        echo ""
        echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  🎉 SETUP SELESAI — Sistem siap beroperasi!                 ║${NC}"
        echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}║                                                              ║${NC}"
        echo -e "${GREEN}║  • Backup otomatis: Setiap hari 02:00 AM                    ║${NC}"
        echo -e "${GREEN}║  • Log tersimpan  : /var/log/backup.log                     ║${NC}"
        echo -e "${GREEN}║  • Retention      : 7 hari (lokal & remote)                 ║${NC}"
        echo -e "${GREEN}║  • Restore        : /root/scripts/restore.sh                ║${NC}"
        echo -e "${GREEN}║                                                              ║${NC}"
        echo -e "${GREEN}║  Untuk test manual: bash ${SCRIPTS_DIR}/backup.sh           ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    else
        log_warning "Ada ${FAIL} komponen yang belum terkonfigurasi. Periksa dan selesaikan secara manual."
    fi
    echo ""
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================
print_header
check_root
install_dependencies
setup_directories
deploy_scripts
setup_credentials
setup_rclone
setup_cronjob
setup_logrotate
final_validation
