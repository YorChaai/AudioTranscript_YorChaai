# Panduan Melakukan Git Push

Dokumen ini berisi langkah-langkah dasar untuk melakukan sinkronisasi kode dari lokal (komputer Anda) ke remote repository (seperti GitHub, GitLab, atau Bitbucket).

## 1. Cek Status Perubahan
Sebelum melakukan *commit*, pastikan file apa saja yang telah diubah dengan menggunakan perintah:
```bash
git status
```

## 2. Tambahkan Perubahan (Staging)
Untuk menambahkan semua file yang berubah agar siap di-commit:
```bash
git add .
```
> *Catatan: Tanda titik `.` berarti memasukkan semua file yang ada di folder saat ini. Jika Anda hanya ingin menambahkan file tertentu, gunakan `git add nama_file`.*

## 3. Buat Commit
Simpan perubahan tersebut ke dalam riwayat lokal dengan pesan yang menjelaskan apa yang Anda ubah:
```bash
git commit -m "Pesan commit Anda di sini"
```
> *Contoh: `git commit -m "fix: memperbaiki renderflex overflow pada transcribe screen"`*

## 4. Push ke Remote Repository
Langkah terakhir adalah mengirimkan (push) *commit* tersebut ke server remote:
```bash
git push
```

### Situasi Khusus
Jika Anda membuat branch baru di lokal dan belum ada di server remote, gunakan perintah berikut untuk *push* pertama kalinya:
```bash
git push -u origin nama_branch_anda
```

---
**Tips:** 
Jika terjadi error (misalnya karena ada perubahan di server yang belum Anda miliki di lokal), lakukan `git pull` terlebih dahulu untuk menggabungkan kode sebelum melakukan `git push`.
