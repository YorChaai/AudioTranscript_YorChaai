Di project ini:

`D:\Aplikasi\mathall\mathall`

apakah sudah ada sistem seperti **template/theme** dan **multi-language** seperti yang ada di aplikasi sebelumnya?

Saya ingin versi di sini dibuat lebih rapi dan terstruktur, terutama untuk:

- Sistem **template/theme** yang bagus, konsisten, dan mudah dikembangkan.
- Pilihan bahasa **Indonesia + English**.
- Bisa juga menggunakan mode **full English**.
- Struktur file untuk theme dan language dibuat rapi supaya nanti gampang ditambah atau diubah tanpa mengacak bagian lain.

Kalau belum ada, tolong dibuatkan sistemnya dengan struktur yang bagus dan reusable.

Tapi sebelum masuk ke bagian theme dan bahasa, saya ingin bereskan masalah **upload/import file** dulu.

Sekarang proses upload terasa sangat lama. Tolong cek apakah prosesnya masih dilakukan satu per satu. Kalau iya, apakah bisa dibuat menggunakan **multiple/concurrent processing** supaya beberapa file bisa diproses bersamaan dan jauh lebih cepat?

Tetapi jangan sampai optimasi ini merusak file MP3 atau menurunkan kualitas hasil konversi video ke MP3.

Saya juga ingin proses import dibuat lebih pintar:

- Kalau file sudah **MP3**, jangan di-convert lagi. Langsung gunakan file MP3 tersebut.
- Kalau file **MP4/video**, baru ambil/convertnya menjadi audio MP3.
- Kalau dalam satu folder terdapat file MP3 dan MP4 dengan isi/nama yang sebenarnya sama, jangan sampai keduanya diproses dan menghasilkan duplikat.
- Sistem harus bisa mendeteksi tipe file terlebih dahulu sebelum menentukan proses berikutnya.
- Jangan melakukan proses konversi yang tidak diperlukan karena hanya membuat import semakin lama.
- Kalau memungkinkan, gunakan proses paralel/concurrent dengan batas worker yang aman supaya tetap cepat tanpa membuat aplikasi freeze atau penggunaan CPU/RAM terlalu tinggi.

Tolong cek juga bottleneck upload/import saat ini. Saya ingin solusinya bukan hanya membuat progress terlihat lebih cepat, tetapi memang mempercepat proses sebenarnya.

Urutan pengerjaannya:

1. Perbaiki dan optimalkan sistem upload/import terlebih dahulu.
2. Pastikan MP3 tidak diproses ulang dan MP4 hanya dikonversi jika memang diperlukan.
3. Tambahkan multiple/concurrent processing yang aman.
4. Setelah itu baru rapikan sistem **template/theme**.
5. Terakhir buat sistem bahasa **Indonesia, English, dan full English** dengan struktur yang reusable.
