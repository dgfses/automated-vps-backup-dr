Project Automasi Cloud Backup & Disaster Recovery ini adalah salah satu project paling kuat yang bisa kamu pamerkan. Di dunia cloud hosting, ada satu hukum besi bagi System Administrator: "Backup yang tidak pernah diuji coba pemulihannya (restore) bukanlah backup, melainkan harapan kosong."

Perusahaan hosting menghadapi dua ancaman terbesar setiap harinya:

Server Down / Hacker / Ransomware: Klien kehilangan data dan menuntut pemulihan cepat.

Disk Server Penuh (100% Disk Usage): Sering terjadi karena file backup menumpuk di dalam server itu sendiri tanpa pernah dihapus, yang akhirnya membuat database crash.

Berikut adalah bedah total bagaimana sistem ini bekerja, apa saja yang perlu kamu buat, dan bagaimana cara mengemasnya menjadi portofolio GitHub yang kelas atas.

1. Alur Kerja Sistem (How It Works)
Secara konsep, kamu akan membuat sebuah skrip (Bash Script .sh atau Python .py) yang berjalan secara otomatis di balik layar tanpa interaksi manusia. Alur kerjanya terbagi menjadi 5 tahap:

[Cronjob Trigger (02:00 AM)] 
       │
       ▼
[1. Dump Database & Compress Folder Web] 
       │
       ▼
[2. Upload ke Remote Storage via Rclone (GDrive/S3)] 
       │
       ▼
[3. Cleanup / Retention Policy (Hapus backup > 7 hari)] 
       │
       ▼
[4. Kirim Laporan Status ke Telegram / Discord]
2. Bedah 4 Fitur Utama & Cara Implementasinya
A. Ekstraksi & Kompresi Data (Backup Lokal Sementara)
Skrip harus mengamankan dua komponen utama dari sebuah website: Database (isi konten/user) dan File Web (kode source, gambar, plugin).

Database: Menggunakan perintah mysqldump untuk mengekspor database MariaDB/MySQL menjadi file .sql.

File Web: Menggunakan perintah tar -czf untuk membungkus seluruh folder website (misalnya /var/www/html) bersama file .sql tadi menjadi satu arsip terkompresi berformat .tar.gz.

Kenapa .tar.gz? Karena format ini menjaga struktur izin file (file permissions) di Linux dan ukurannya jauh lebih kecil sehingga hemat kuota transfer.

B. Pengiriman ke Remote Storage (Offsite Backup)
Menyimpan file backup di server yang sama adalah kesalahan fatal. Jika server rusak atau terkena hack, file backup ikut lenyap.

Kamu bisa memanfaatkan tool bernama rclone (sering disebut sebagai "pisau Swiss Army untuk cloud storage" di dunia Linux).

Dengan rclone, skripmu akan otomatis meng-upload file .tar.gz yang baru dibuat ke penyimpanan eksternal gratisan seperti Google Drive, Cloudflare R2, atau AWS S3.

C. Retention Policy (Mencegah Disk Server Penuh)
Ini adalah fitur yang sangat disukai oleh SysAdmin senior. Kamu mengimplementasikan logika untuk membersihkan file lama agar kapasitas Hard Disk / SSD VPS tidak jebol.

Di dalam skrip, kamu masukkan perintah Linux untuk mencari dan menghapus file backup lokal maupun remote yang usianya sudah lebih dari 7 hari.

Contoh logika di terminal Linux: find /path/to/backup -type f -mtime +7 -delete. Ini membuktikan kamu sadar akan manajemen sumber daya server (resource management).

D. Notifikasi Real-Time (Observability)
SysAdmin tidak mungkin mengecek server satu per satu setiap pagi hanya untuk tahu apakah backup tadi malam berhasil atau gagal.

Menggunakan fitur Webhook Discord atau Telegram Bot API via perintah curl / modul requests Python.

Setelah proses upload selesai, skrip akan mengirimkan pesan otomatis ke grup Telegram kamu dengan format laporan:

🟢 STATUS: SUCCESS (atau 🔴 FAILED)

📅 Waktu Eksekusi: 02:00:15 WIB

📦 Nama File: backup-web-20260705.tar.gz

⚖️ Ukuran File: 145 MB

⏳ Durasi Proses: 45 detik

3. Penataan Jadwal Otomatis (Linux Cronjob)
Setelah skrip automasi (misalnya bernama auto_backup.sh) selesai dibuat dan diuji coba secara manual, langkah selanjutnya adalah mendaftarkannya ke sistem penjadwalan Linux yaitu Cronjob.

Dengan mengetikkan perintah crontab -e di terminal server, kamu cukup menambahkan satu baris aturan sintaks waktu. Misalnya:

Bash
0 2 * * * /bin/bash /root/scripts/auto_backup.sh >> /var/log/backup.log 2>&1
Artinya: "Jalankan skrip auto_backup.sh setiap hari tepat pada pukul 02:00 pagi (saat trafik website sedang sepi), dan catat seluruh riwayat eksekusinya ke dalam file log."

4. Nilai Jual Utama: Simulasi "Disaster Recovery" (DR)
Bagian ini adalah puncak dari portofolio kamu. Di dalam repositori GitHub, buatlah satu bagian khusus di README.md berjudul "Disaster Recovery Simulation (Studi Kasus Pemulihan Server)".

Tuliskan skenario seolah-olah website klien mengalami kehancuran total (misalnya database tidak sengaja terhapus atau server di-reset ulang), lalu tunjukkan panduan step-by-step bagaimana kamu memulihkannya dalam waktu di bawah 10 menit menggunakan skripmu:

Step 1: Download Arsip Terakhir: Mengambil file backup .tar.gz terbaru dari remote storage (Google Drive/S3) kembali ke server baru.

Step 2: Ekstraksi File Web: Membongkar arsip tar -zxvf backup-web.tar.gz -C /var/www/html/ untuk mengembalikan seluruh file website.

Step 3: Restore Database: Mengimpor kembali file database ke dalam sistem menggunakan perintah mysql -u root -p nama_db < database_backup.sql.

Step 4: Verifikasi: Melakukan pengetesan endpoint HTTP untuk memastikan website sudah kembali online dengan normal (HTTP 200 OK).

Why This Works (Kenapa Ini Sangat Kuat untuk Magang)
Ketika Tim Teknis Jetorbit melihat portofolio ini di GitHub kamu, kesimpulan yang mereka dapatkan adalah:

Kamu tidak hanya bisa koding/scripting, tapi kamu paham infrastruktur Linux dan manajemen server.

Kamu sadar akan pentingnya efisiensi storage (karena ada retention policy).

Kamu memiliki pola pikir preventif dan proaktif (ada notifikasi Telegram & simulasi Disaster Recovery).

Kombinasi project Apify Scraper (Python/Automasi/Real Users) ditambah project Cloud Backup & DR (Linux/SysAdmin/Infrastruktur) ini membuat profilmu terlihat jauh lebih matang dibandingkan pelamar magang pada umumnya.