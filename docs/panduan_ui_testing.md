# Panduan Lengkap Automated UI & Widget Testing di Flutter

> **Dokumen Referensi & Best Practices Pengujian Otomatis Antarmuka (UI Testing) Menggunakan Flutter & Dart**
> *Ditulis untuk dokumentasi arsitektur proyek `Audio to Text AI Studio` dan panduan adopsi pada aplikasi Flutter lainnya.*

---

## Daftar Isi
1. [Pengantar: Apa Itu Automated UI & Widget Testing?](#1-pengantar-apa-itu-automated-ui--widget-testing)
2. [Tiga Tingkatan Pengujian dalam Ekosistem Flutter](#2-tiga-tingkatan-pengujian-dalam-ekosistem-flutter)
3. [Mengapa Automated UI Testing Sangat Krusial?](#3-mengapa-automated-ui-testing-sangat-krusial)
4. [Anatomi & Komponen Utama `flutter_test`](#4-anatomi--komponen-utama-flutter_test)
5. [Bedah Kode: Cara Kerja `ui_interaction_test.dart`](#5-bedah-kode-cara-kerja-ui_interaction_testdart)
6. [Cara Menjalankan dan Membaca Hasil Test](#6-cara-menjalankan-dan-membaca-hasil-test)
7. [Contoh Kasus Nyata: Bug yang Berhasil Dicegah](#7-contoh-kasus-nyata-bug-yang-berhasil-dicegah)
8. [Panduan Langkah Demi Langkah Menerapkan UI Testing di Aplikasi Lain](#8-panduan-langkah-demi-langkah-menerapkan-ui-testing-di-aplikasi-lain)
9. [Tips & Best Practices Menulis Test yang Tangguh](#9-tips--best-practices-menulis-test-yang-tangguh)
10. [Kesimpulan & Checklist Kualitas](#10-kesimpulan--checklist-kualitas)

---

## 1. Pengantar: Apa Itu Automated UI & Widget Testing?

Dalam pengembangan perangkat lunak modern, pengujian antarmuka pengguna (*User Interface / UI Testing*) secara manual dengan cara mengklik tombol satu per satu di perangkat fisik atau emulator membutuhkan waktu yang sangat lama, rentan terhadap kelalaian manusia (*human error*), dan tidak efisien jika aplikasi memiliki puluhan layar dengan ratusan kemungkinan interaksi.

**Automated UI & Widget Testing** adalah mekanisme di mana kita menulis kode program (skrip pengujian) yang bertindak layaknya seorang pengguna virtual (robot penguji). Robot ini secara otomatis:
- Membuka layar aplikasi dalam hitungan milidetik.
- Menemukan tombol, dropdown, form input, atau kartu menu tertentu.
- Melakukan gesture seperti klik (*tap*), geser (*scroll / drag*), ketik teks (*enter text*), atau tahan (*long press*).
- Memvalidasi apakah sistem memberikan respons visual yang benar tanpa mengalami *crash*, *freeze*, atau *error rendering*.

Fitur ini **100% bawaan resmi dari Flutter SDK dan bahasa pemrograman Dart** melalui pustaka standar `package:flutter_test/flutter_test.dart`.

---

## 2. Tiga Tingkatan Pengujian dalam Ekosistem Flutter

Untuk memahami di mana posisi UI/Widget Testing berada, Flutter membagi piramida pengujian menjadi tiga tingkatan:

```
        / \
       /   \      3. Integration Testing (Uji End-to-End di Real Device)
      / ----\
     /       \    2. Widget / UI Testing (Simulasi Interaksi Widget Virtual)
    / --------\
   /           \  1. Unit Testing (Uji Fungsi Logika Murni / API Service)
  /-------------\
```

| Tingkatan | Kecepatan Eksekusi | Kebutuhan Emulator/Device | Fokus Pengujian |
| :--- | :--- | :--- | :--- |
| **1. Unit Test** | Sangat Cepat (< 1 detik) | Tidak Perlu | Fungsi matematika, parser JSON, model data, enkripsi string. |
| **2. Widget/UI Test** | Cepat (~ 1-2 detik) | Tidak Perlu (Headless Canvas) | Interaksi tombol, perpindahan state tema/bahasa, validasi layout & overflow. |
| **3. Integration Test** | Lambat (30-60 detik) | Wajib Ada Device / Simulator | Alur penuh aplikasi từ login, rekam mikrofon, hingga sistem berkas OS nyata. |

**Widget Testing** merupakan *sweet spot* terbaik: memberikan keyakinan tinggi bahwa UI berfungsi dengan baik tanpa harus menunggu proses kompilasi aplikasi ke APK/EXE yang memakan waktu lama.

---

## 3. Mengapa Automated UI Testing Sangat Krusial?

1. **Mencegah Masalah Regresi (Regression Bug)**:
   Ketika pengembang menambahkan fitur baru (misal: fitur ganti tema atau ganti bahasa), seringkali perubahan tersebut tanpa disengaja merusak tombol di halaman lain. UI Test memastikan fitur lama tetap aman setelah penambahan fitur baru.
2. **Menangkap Error `RenderFlex Overflow` Lebih Awal**:
   Masalah klasik di Flutter adalah garis kuning-hitam garis belang (*A RenderFlex overflowed by X pixels*). Widget test dapat diset ke berbagai ukuran layar (mobile, tablet, desktop 4K) untuk menguji responsivitas layout sebelum aplikasi dirilis ke publik.
3. **Mendeteksi Error Konteks Material (`No Material widget found`)**:
   Beberapa komponen Flutter (seperti `InkWell`, `ListTile`, `DropdownButton`) wajib berada di bawah widget `Material` atau `Scaffold`. Jika lupa menyertakan Material, UI Test akan langsung melempar peringatan merah saat tes dijalankan.
4. **Efisiensi Waktu & Biaya**:
   Menjalankan 50 skenario uji coba secara manual butuh waktu 30-45 menit. Dengan automated test, 50 skenario tersebut selesai dieksekusi hanya dalam waktu **2-3 detik**.
5. **Zero Production Overhead**:
   Semua kode pengujian diletakkan di direktori `/test` di luar `/lib`. Saat aplikasi di-build menjadi APK atau file `.exe`, kode pengujian **tidak ikut terkompilasi**, sehingga tidak menambah ukuran aplikasi 1 byte pun.

---

## 4. Anatomi & Komponen Utama `flutter_test`

Untuk menulis pengujian UI di Flutter, kita menggunakan class dan fungsi utama berikut:

### A. `testWidgets`
Fungsi pengganti `test()` standar yang menyediakan objek `WidgetTester` untuk mengontrol siklus hidup widget virtual:
```dart
testWidgets('Deskripsi skenario uji', (WidgetTester tester) async {
  // Kode pengujian di sini
});
```

### B. `tester.pumpWidget` & `tester.pumpAndSettle`
- `tester.pumpWidget(Widget)`: Merender pohon widget (*Widget Tree*) ke dalam memori lingkungan pengujian.
- `tester.pump()`: Memajukan frame animasi sebanyak 1 frame (biasanya 16.6ms).
- `tester.pumpAndSettle()`: Menunggu seluruh animasi, transisi layar, fade, dan rebuild selesai hingga antarmuka stabil dan diam.

### C. `find` (Widget Finder)
Alat untuk menemukan elemen UI tertentu di layar:
- `find.text('Simpan')`: Menemukan widget teks dengan kata "Simpan".
- `find.byType(ElevatedButton)`: Menemukan tombol bertipe `ElevatedButton`.
- `find.byIcon(Icons.settings)`: Menemukan ikon tertentu.
- `find.byKey(Key('my_unique_button'))`: Menemukan widget berdasarkan ID unik (Key).

### D. `tester.tap`, `tester.drag`, `tester.enterText`
Metode untuk mensimulasikan interaksi fisik pengguna:
- `await tester.tap(finder)`: Melakukan klik pada widget yang ditemukan.
- `await tester.drag(finder, Offset(0, -300))`: Menggulung layar ke bawah sejauh 300 piksel.
- `await tester.enterText(finder, 'Halo Dunia')`: Mengetikkan teks ke dalam `TextField`.

### E. `expect` (Assertion Matcher)
Memvalidasi apakah kondisi akhir sesuai dengan ekspektasi:
- `expect(find.byType(SettingsDialog), findsOneWidget);`: Memastikan dialog pengaturan terbuka tepat 1 buah.
- `expect(find.text('Error'), findsNothing);`: Memastikan tidak ada teks error yang muncul.

---

## 5. Bedah Kode: Cara Kerja `ui_interaction_test.dart`

Mari kita bedah arsitektur file pengujian yang telah kita buat pada proyek ini:

```dart
// 1. Helper function untuk membungkus halaman dengan semua Provider yang dibutuhkan
Widget createTestApp(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider(create: (_) => LanguageProvider()),
      ChangeNotifierProvider(create: (_) => ConnectionService()),
      ChangeNotifierProvider(create: (_) => TranscribeProvider()),
      // ... provider lainnya
    ],
    child: Consumer2<ThemeProvider, LanguageProvider>(
      builder: (context, themeProv, langProv, _) {
        return MaterialApp(
          theme: themeProv.currentThemeData,
          home: Scaffold(body: child),
        );
      },
    ),
  );
}
```

### Skenario 1: Menguji Pergantian Tema & Bahasa Tanpa Error
```dart
testWidgets('1. SettingsDialog opens, switches themes and languages without error', (tester) async {
  // Set resolusi layar virtual ke ukuran Desktop (1280 x 1000)
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  // Render tombol pembuka dialog
  await tester.pumpWidget(createTestApp(
    Builder(builder: (ctx) => ElevatedButton(
      onPressed: () => SettingsDialog.show(ctx),
      child: const Text('Open Settings'),
    )),
  ));
  await tester.pumpAndSettle();

  // 1. Klik buka dialog
  await tester.tap(find.text('Open Settings'));
  await tester.pumpAndSettle();
  expect(find.byType(SettingsDialog), findsOneWidget);

  // 2. Klik ganti ke bahasa Inggris
  await tester.tap(find.text('English'));
  await tester.pumpAndSettle();

  // 3. Klik tema OLED Dark, Neon Purple, Emerald Teal, Light Studio
  await tester.tap(find.text('OLED Pure Black'));
  await tester.pumpAndSettle();

  // Scroll jika opsi berada di bawah
  await tester.drag(find.byType(ListView).last, const Offset(0, -300));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Light Studio'));
  await tester.pumpAndSettle();

  // 4. Tutup dialog
  await tester.tap(find.text('Close'));
  await tester.pumpAndSettle();
  expect(find.byType(SettingsDialog), findsNothing);
});
```

---

## 6. Cara Menjalankan dan Membaca Hasil Test

### Menjalankan Semua Pengujian via Terminal
Buka terminal pada direktori root Flutter app dan jalankan:
```bash
flutter test
```

### Menjalankan File Tertentu
```bash
flutter test test/ui_interaction_test.dart
```

### Menjalankan Skenario Tertentu
```bash
flutter test --plain-name="SettingsDialog"
```

### Membaca Laporan Output
Jika semua tes berhasil:
```
00:01 +10: All tests passed!
```
- Angka `+10` berarti terdapat 10 skenario uji yang sukses dijalankan.
- Jika ada kegagalan, Flutter akan memberikan stack trace detail berupa baris file, nama widget yang bermasalah, serta penyebab spesifiknya (apakah teks tidak ditemukan, overflow piksel, atau unhandled exception).

---

## 7. Contoh Kasus Nyata: Bug yang Berhasil Dicegah

Ketika kita menjalankan `ui_interaction_test.dart` pertama kali, sistem pengujian otomatis berhasil menemukan **3 bug tersembunyi** yang sebelumnya tidak terlihat secara kasat mata:

1. **Bug `No Material widget found` pada `FileBrowserScreen`**:
   - *Masalah*: Tombol breadcrumb `InkWell` digunakan di dalam widget tanpa ancestor `Material`.
   - *Dampak jika lolos*: Pengguna di perangkat Android/Windows akan mengalami crash layar merah saat menavigasi folder server.
   - *Solusi yang diterapkan*: Membungkus `SafeArea` dengan `Scaffold(backgroundColor: Colors.transparent, ...)`.

2. **Bug `RenderFlex overflowed by 68 pixels` pada `SummaryScreen`**:
   - *Masalah*: Baris header `Row` di panel file transkripsi menggunakan `const Spacer()` kaku yang mendorong menu sort dan tombol refresh keluar layar pada sidebar sempit (lebar < 280px).
   - *Dampak jika lolos*: Muncul garis belang kuning-hitam di UI.
   - *Solusi yang diterapkan*: Mengubah teks judul menjadi `Expanded(child: Text(..., overflow: TextOverflow.ellipsis))` tanpa Spacer.

3. **Bug Dropdown Overflow di `TranscribeSidebar`**:
   - *Masalah*: Komponen `DropdownButtonFormField` pada opsi pemilihan bahasa meluap saat sidebar dibuka di layar kecil.
   - *Solusi yang diterapkan*: Menambahkan properti `isExpanded: true`.

---

## 8. Panduan Langkah Demi Langkah Menerapkan UI Testing di Aplikasi Lain

Jika Anda ingin menerapkan sistem pengujian otomatis yang sama pada aplikasi Flutter Anda yang lain (misal: *Mathall*, aplikasi toko online, sistem kasir, atau aplikasi kantor), ikuti panduan berikut:

### Langkah 1: Pastikan `flutter_test` Ada di `pubspec.yaml`
```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
```

### Langkah 2: Buat Folder `test/`
Buat struktur file pengujian yang rapi:
```
my_app/
├── lib/
│   ├── main.dart
│   ├── screens/
│   │   ├── login_screen.dart
│   │   └── home_screen.dart
└── test/
    ├── unit/
    │   └── auth_service_test.dart
    ├── widgets/
    │   ├── login_ui_test.dart
    │   └── home_ui_test.dart
    └── smoke_test.dart
```

### Langkah 3: Buat Mock / Test Wrapper untuk State Management
Jika aplikasi Anda menggunakan `Provider`, `Bloc`, atau `Riverpod`, buat fungsi helper `createTestApp` agar widget yang diuji selalu memiliki akses ke state yang valid tanpa perlu memanggil API server asli:
```dart
Widget createTestApp(Widget screen) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => MockAuthProvider()),
      ChangeNotifierProvider(create: (_) => MockSettingsProvider()),
    ],
    child: MaterialApp(home: screen),
  );
}
```

### Langkah 4: Tulis Uji Interaksi Alur Pengguna (User Flow)
Contoh pengujian form login:
```dart
testWidgets('Pengguna bisa mengetik email dan menekan tombol login', (tester) async {
  await tester.pumpWidget(createTestApp(const LoginScreen()));
  await tester.pumpAndSettle();

  // 1. Ketik email & password
  await tester.enterText(find.byKey(const Key('email_input')), 'user@gmail.com');
  await tester.enterText(find.byKey(const Key('password_input')), 'rahasia123');

  // 2. Klik tombol Login
  await tester.tap(find.text('Masuk'));
  await tester.pumpAndSettle();

  // 3. Pastikan loading atau halaman Home muncul
  expect(find.text('Selamat Datang!'), findsOneWidget);
});
```

---

## 9. Tips & Best Practices Menulis Test yang Tangguh

1. **Gunakan `Key` untuk Widget Kritis**:
   Daripada mencari tombol berdasarkan teks yang mungkin berubah karena multi-bahasa (`find.text('Login')`), gunakan `Key`:
   ```dart
   ElevatedButton(
     key: const Key('btn_submit_order'),
     onPressed: () => submitOrder(),
     child: Text(tr('submit')),
   )
   ```
   Lalu di pengujian cukup gunakan `find.byKey(const Key('btn_submit_order'))`.

2. **Atur Ukuran Layar Sesuai Target Target Device**:
   Jika aplikasi ditujukan untuk tablet atau desktop, selalu set `tester.view.physicalSize`:
   ```dart
   tester.view.physicalSize = const Size(1920, 1080); // Full HD Desktop
   tester.view.devicePixelRatio = 1.0;
   addTearDown(tester.view.resetPhysicalSize);
   ```

3. **Gunakan `SharedPreferences.setMockInitialValues({})`**:
   Jika aplikasi menggunakan penyimpanan lokal, inisialisasikan mock di method `setUp()` agar pengujian tidak bergantung pada penyimpanan fisik perangkat:
   ```dart
   setUp(() {
     SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
   });
   ```

4. **Hindari Network Request Nyata di Widget Test**:
   Widget test berjalan di lingkungan headless tanpa koneksi HTTP. Pastikan class repository atau API Service menggunakan mock atau data lokal tiruan saat pengujian dijalankan.

5. **Gabungkan dengan CI/CD (Continuous Integration)**:
   Di platform seperti GitHub Actions atau GitLab CI, Anda bisa memasang perintah otomatis:
   ```yaml
   - name: Run Tests
     run: flutter test
   ```
   Sehingga jika ada kode yang menyebabkan error pada UI, sistem otomatis menolak penggabungan kode (*Pull Request / Merge*).

---

## 10. Kesimpulan & Checklist Kualitas

Automated UI & Widget Testing adalah pilar utama dalam menciptakan aplikasi Flutter kelas enterprise yang stabil, cepat, dan bebas dari bug rendering.

### Checklist Kualitas Sebelum Merilis Aplikasi:
- [x] Menjalankan `flutter analyze` dan memastikan **0 issue / warning**.
- [x] Menjalankan `flutter test` dan memastikan **100% test suite passed**.
- [x] Semua tombol utama memiliki pengujian klik otomatis.
- [x] Semua modal dialog dan popup terverifikasi bisa dibuka dan ditutup dengan benar.
- [x] Responsivitas layout teruji di resolusi kecil (mobile 360px) dan besar (desktop 1280px+).

---
*Dokumen ini dibuat secara otomatis sebagai panduan standar kualitas pengembangan aplikasi.*
