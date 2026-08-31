# Panduan Mendalam Penggunaan Postman: Membedah Anatomi Request API

Ketika Anda membuka aplikasi Postman dan membuat sebuah *Request* baru, Anda akan disajikan dengan sederet *tab* atau menu horisontal. Menu-menu ini—mulai dari **Params**, **Authorization**, **Headers**, **Body**, hingga **Scripts** dan **Tests**—adalah "jantung" dari bagaimana kita berkomunikasi dengan sebuah server. 

Panduan ini (dengan panjang ~800 kata) akan membedah secara mendalam fungsi masing-masing *tab* tersebut dan bagaimana mereka bekerja secara nyata, terutama jika dikaitkan dengan aplikasi **Audio Convert API** yang baru saja Anda tes.

---

## 0. Tahap Persiapan: Membuat Collection dan Request Baru

Sebelum kita membedah isi (anatomi) dari sebuah *request*, Anda tentu harus tahu cara membuat dan menyusun *request* itu sendiri dari nol. Berikut adalah langkah-langkah kasarnya:

### A. Membuat "Wadah" Utama (Collection)
Collection itu ibarat buku catatan besar atau map utama untuk mengelompokkan semua API dari proyek Anda agar rapi.
1. Di panel paling kiri Postman, klik tanda **+ (Plus)** di bagian atas tulisan *Collections*, lalu pilih **Blank collection** (Koleksi Kosong).
2. Sebuah Collection baru akan muncul. Klik kanan (atau tekan tombol *F2*) pada namanya untuk mengganti nama (misal: "Aplikasi Audio Saya").
*(Tips: Di dalam Collection ini, Anda juga bisa membuat folder-folder kecil dengan cara klik kanan > **Add folder**).*

### B. Membuat Request Baru
1. Klik kanan (atau klik lambang titik tiga `...`) pada nama Collection (atau Folder) Anda.
2. Pilih **Add request** (Tambahkan Permintaan).
3. Ganti nama *request* yang baru muncul sesuai dengan fiturnya (misalnya: "Cek Server" atau "Upload Audio").
4. Perhatikan ke panel tengah. Di sebelah kiri kolom teks panjang, pilih **Metode HTTP** yang sesuai (seperti `GET` untuk mengambil data, `POST` untuk mengirim data).
5. Di kolom URL panjang sebelahnya, ketikkan alamat lengkap server Anda (contoh: `http://localhost:5000/api/health`).

Setelah sebuah *request* dibuat, barulah Anda akan menggunakan menu-menu *tab* di bawahnya (Params, Headers, Body, dll) untuk melengkapi "surat" Anda sebelum menekan tombol **Send** biru di sebelah kanan. Mari kita bedah fungsi *tab* tersebut satu per satu:

---

## 1. Tab "Params" (Parameters)
**Fungsi Utama:** Mengirimkan data tambahan melalui URL secara langsung.

Di dunia API, "Params" dibagi menjadi dua jenis utama yang sering digabungkan penggunaannya:
* **Query Parameters:** Ini adalah data yang menempel di ujung URL setelah tanda tanya `?`. Misalnya: `http://localhost:5000/api/search?keyword=gitar&page=2`. Di Postman, jika Anda mengisi tabel di tab *Params*, Postman akan otomatis merakit bagian `?keyword=gitar` tersebut ke dalam URL Anda. Ini sangat sering dipakai untuk fitur pencarian (*search*), penyaringan (*filter*), atau penomoran halaman (*pagination*).
* **Path Variables:** Ini adalah data dinamis yang menjadi *bagian dari jalur* URL itu sendiri. Dalam aplikasi Anda, kita menggunakan Path Variables saat mengecek status transkrip atau mengunduh teks. Contohnya URL: `{{base_url}}/api/transcript/:filepath`. Tanda titik dua `:` di depan kata `filepath` memberitahu Postman bahwa kata tersebut adalah *variabel* yang nilainya bisa diubah-ubah. Tab *Params* di Postman menyediakan kolom khusus untuk mengisi nilai dari `:filepath` ini (seperti yang Anda lakukan saat menempelkan `output/single/BTS_Spring...txt`). 

> **Kapan Digunakan?** Gunakan tab *Params* saat Anda melakukan request jenis **GET** (mengambil data), karena request tipe GET pada dasarnya tidak boleh memiliki *Body*. Semua data filter atau ID spesifik harus disematkan di URL melalui Params.

---

## 2. Tab "Authorization"
**Fungsi Utama:** Membuktikan siapa Anda kepada server (Proses Otentikasi/Log In).

Sebuah server API yang aman tidak akan membiarkan sembarang orang mengakses datanya. Mereka butuh "KTP" atau "Tiket Masuk". Tab *Authorization* di Postman adalah tempat khusus yang disediakan untuk menaruh tiket masuk tersebut.
* Postman mendukung banyak jenis standar otentikasi di industri, seperti **Basic Auth** (mengirim username dan password), **Bearer Token** (mengirim token panjang rahasia yang biasa dipakai di aplikasi modern/JWT), dan **OAuth 2.0** (seperti tombol "Login with Google").
* **Di Aplikasi Anda:** Aplikasi Audio Convert Anda menggunakan sistem *API Key* bernama `X-Api-Key`. Meski Postman memiliki opsi *API Key* di tab *Authorization*, dalam praktik nyatanya, *API Key* seringkali dikirimkan melalui tab **Headers**. 

> **Kapan Digunakan?** Gunakan tab ini jika dokumentasi API yang Anda gunakan secara tegas meminta penggunaan *Bearer Token*, *OAuth*, atau jika Anda ingin Postman mengotomatiskan pengisian data keamanan.

---

## 3. Tab "Headers"
**Fungsi Utama:** Mengirim "Metadata" atau informasi rahasia di balik layar tentang request Anda.

Jika *Body* adalah isi dari sebuah surat, maka *Headers* adalah **amplopnya**. Amplop ini berisi cap pos, keterangan jenis surat, siapa pengirimnya, dan instruksi khusus untuk tukang pos (server). 
Beberapa fungsi krusial dari Headers:
* `Content-Type`: Memberitahu server wujud data apa yang Anda kirim. Apakah teks biasa? Gambar? Atau JSON? Postman sering mengisi ini secara otomatis.
* `Accept`: Memberitahu server bentuk balasan apa yang Anda harapkan (misalnya Anda hanya mau menerima format XML atau JSON).
* **Otentikasi Kustom:** Nah, di sinilah aplikasi Anda bekerja. Aplikasi Audio Convert Anda mewajibkan adanya "cap khusus" di amplop tersebut yang bernama `X-Api-Key` dengan nilai `YORCHAAI_SECRET_KEY`. Jika amplop Anda tidak memiliki cap ini, aplikasi Anda akan menolak surat tersebut (ditolak dengan status 401 Unauthorized).

> **Kapan Digunakan?** Gunakan tab *Headers* untuk menyematkan *API Key* Anda, mengatur bahasa yang diinginkan, atau pengaturan metadata tingkat lanjut lainnya.

---

## 4. Tab "Body"
**Fungsi Utama:** Mengirim "Daging" atau isi utama dari data yang ingin Anda berikan ke server.

Tab *Body* adalah tempat di mana beban kerja terberat terjadi, terutama saat Anda melakukan request **POST**, **PUT**, atau **PATCH** (menyimpan atau mengubah data). Di dalam tab *Body*, ada beberapa format bentuk data yang paling sering digunakan:
* **form-data:** Ini persis seperti ketika Anda mengisi formulir pendaftaran di internet, yang ada tombol "Upload KTP/Foto". Di aplikasi Anda, saat Anda memanggil `POST /api/audio/upload`, Anda menggunakan format *form-data* karena format inilah satu-satunya cara di internet untuk **mengirim file (seperti mp3, mp4)** bersamaan dengan teks.
* **raw (terutama JSON):** Ini adalah format standar industri komunikasi antar program (API) saat ini. Formatnya menggunakan kurung kurawal `{ }` dan sangat terstruktur. Di aplikasi Anda, saat memanggil fitur `Start Transcribe`, Anda mengirimkan instruksi terstruktur berupa JSON untuk memberitahu server file mana yang diproses dan apa bahasa sasarannya. 
* **x-www-form-urlencoded:** Mirip dengan form-data, tapi tidak bisa untuk kirim file, hanya teks saja (jarang dipakai di aplikasi modern selain untuk pengiriman form sederhana).

> **Kapan Digunakan?** Mutlak digunakan saat Anda perlu mengirim file berukuran besar, mengirim instruksi kompleks (JSON), atau mendaftarkan data pengguna baru ke database (POST/PUT).

---

## 5. Tab "Scripts" dan "Tests" (Bonus Lanjutan)
**Fungsi Utama:** Menjadikan Postman cerdas dan otomatis dengan kode JavaScript.

Banyak pemula yang melewatkan dua tab ini, padahal ini adalah fitur yang membedakan pengguna biasa dengan *Software Tester* profesional.
* **Scripts (Pre-request Script):** Tab ini memungkinkan Anda menjalankan kode *sebelum* tombol Send benar-benar ditekan. Contoh: Anda ingin membuat *request* di mana salah satu parameter namanya harus berupa jam dan detik saat ini (selalu berubah). Anda bisa menulis kode di sini untuk mendapatkan waktu saat ini secara otomatis.
* **Tests:** Tab ini menjalankan kode *setelah* respons dari server diterima. 
  **Skenario Keren di Aplikasi Anda:** Ingat saat Anda mendapat `job_id` dari fitur transkrip? Sebagai tester profesional, Anda tidak perlu repot men-*copy* `job_id` itu dan mem-*paste* nya ke *request Transcribe Status*. Di tab *Tests*, Anda bisa menulis satu baris kode JavaScript untuk mengambil `job_id` dari hasil respons, lalu menyimpannya sebagai Variabel Global di Postman secara otomatis! Sehingga di request berikutnya, `job_id` tersebut sudah terisi dengan sendirinya.

### Kesimpulan
Memahami kelima tab ini (Params, Authorization, Headers, Body, dan Tests) adalah kunci untuk menguasai komunikasi API backend. Postman mendesain antarmukanya agar semirip mungkin dengan anatomi protokol HTTP yang sebenarnya, sehingga dengan menguasai Postman, secara tidak langsung Anda telah mempelajari bagaimana internet bekerja di balik layar.
