# Celyx — Home panorama

SwiftUI + MVVM. Buka `celyx.xcodeproj`, pilih scheme **celyx**, lalu Run.
Project saat ini mengikuti deployment target bawaan iOS 27.2. Shader Metal dibundel sebagai `PanoramaShader.txt` dan dikompilasi sekali saat renderer dibuat; tidak memerlukan download komponen Metal Toolchain tambahan pada Xcode.

## Pembagian kerja tim

- `Features/Home/Models`: state kamera, model katalog, dan resolver asset.
- `Features/Home/ViewModels`: interaksi, pencarian, zoom, arah, serta state sheet.
- `Features/Home/Views`: layout SwiftUI, toolbar sistem, tombol kaca bawah, dock lokasi, dan sheet.
- `Features/Home/Services`: sensor Core Motion; lifecycle start/stop mengikuti halaman dan scene.
- `Features/Home/Rendering`: adapter MTKView dan renderer Metal. ViewModel hanya mengirim `SkySceneState`; renderer tidak mengelola navigasi/UI.
- `Resources/environment`, `Resources/sky`: asset v7 dari folder yang diberikan, disalin ke project agar anggota tim tidak bergantung pada folder Downloads.

## Kontrol

Top bar memakai `NavigationStack` dan toolbar native SwiftUI: reset arah di kiri, serta Sekitar, Layers, dan Search di kanan. Ukuran, hit area, dan tampilan tombol mengikuti sistem tanpa kapsul atau kompas Canvas custom.

Geser horizontal/vertikal untuk melihat 360°, cubit untuk zoom 6–100°, tekan tombol arah utara di toolbar untuk reset. Motion tersedia otomatis pada hardware yang mendukung; simulator menggunakan Touch. Zoom maksimal kini 12× dari FOV awal 72° ke 6°. Di bawah FOV 35°, transisi visual memudarkan atmosfer dan foreground; pada FOV 8° latar sudah menjadi ruang angkasa. Zoom menampilkan bintang redup tambahan secara bertahap hingga batas magnitude 6.5 pada FOV 35°, termasuk bintang tanpa nama umum dari katalog. Nama umum bintang muncul di area pusat (maksimal 5 label). Tap label/titik atau hasil pencarian untuk membuka detail. Matahari dirender di panorama sebagai cakram berdiameter sudut sekitar 0.53° dengan pendar atmosfer dan warna lebih hangat dekat horizon. Pendar adalah simulasi visual, bukan foto atau pengukuran cuaca setempat. Detail Matahari memakai pratinjau cakram; tidak ada ikon besar yang menempel di layar. Matahari tersedia lewat pencarian “Matahari”/“Sun”, daftar Sekitar saat di atas horizon, dan label di panorama. Matahari dapat dikoleksi saat ketinggian minimal 15° dan tutupan awan di bawah 75%; posisi memakai arah Matahari dari snapshot astronomi, bukan koordinat katalog tetap. Tombol Sekitar menampilkan katalog di atas horizon. Detail berisi Collect star yang menyimpan catatan lokal bila memenuhi aturan visibilitas dan altitude minimal 15°. Tombol search memusatkan bintang yang dipilih, layers mengatur Milky Way/bintang/grid/garis rasi. Tombol sparkles kanan bawah membuka Garden / Your Galaxy. Garis rasi tetap dapat diatur lewat Layers. Dock lokasi dan tombol kiri bawah membuka pengaturan pengamatan.

Renderer membaca gambar equirectangular berdasarkan arah ray (tanpa sphere UV yang terbalik), menggabungkan sky → Milky Way → katalog bintang/garis → pulau → laut → perahu malam. Katalog bintang disimpan sekali sebagai vertex buffer 3D dan digambar dalam satu draw call point sprites GPU; inti dan glow tetap bulat dalam koordinat layar, termasuk dekat kutub dan tepi layar. Hanya garis rasi yang dibake menjadi tekstur. Background, bintang, dan foreground memakai proyeksi stereografik yang sama untuk menjaga bentuk lokal saat melihat ke atas. Perahu tetap di dunia saat kamera diputar dan bergoyang dengan dua gelombang sinus sesuai panduan; Reduce Motion mematikan goyangan.

## Performa renderer

Target refresh 60 FPS, render target maksimal 2× ukuran point, dan dua frame maksimal dalam antrean GPU. Tekstur kerja diturunkan sesuai detail masing-masing layer, dinormalisasi RGBA8, dan memakai mipmap. Anggaran alokasi tekstur diuji maksimal 160 MiB (bukan angka total memori app). Gambar sumber tetap utuh. Saat app tidak aktif renderer berhenti; saat Reduce Motion aktif renderer menggambar hanya ketika state berubah. FPS di iPhone fisik belum diprofiling dengan Instruments.

## Posisi saat ini dan estimasi

GPS (atau koordinat manual yang dipilih pengguna) dan Date() menentukan orientasi langit. Tidak ada fallback lokasi diam-diam. Astronomy Engine C upstream dipin di Vendor/AstronomyEngine, diimpor melalui celyx-Bridging-Header.h. Rotasi J2000 ke horizon memperhitungkan precession/nutation; posisi Matahari dan Bulan mengatur fase langit dan estimasi kecerlangan. Snapshot diperbarui tiap 5 detik. Katalog GPU tetap berupa vektor equatorial; perubahan waktu/lokasi hanya mengganti basis.

Gyro memakai GPS perangkat dan referensi utara sejati setelah kalibrasi selesai. Tidak ada fallback relatif atau offset drag; gesture pandangan hanya aktif pada mode Sentuh. Ketepatan tetap dibatasi akurasi kompas perangkat.

Pilihan cahaya sekitar masih manual. Online conditions bersifat opt-in: koordinat dikirim ke Open-Meteo untuk cloud_cover, aerosol_optical_depth dan pm2_5. Model awan/AOD dipakai untuk estimasi, PM2.5 hanya konteks. Cache 30 menit, data lebih dari 3 jam ditolak, null/error tetap unknown. Free endpoint dipakai untuk prototipe non-komersial; evaluasi paket sebelum rilis komersial. Credits tersedia di Layers.

Ilustrasi detail memakai PNG referensi pemilik di Assets.xcassets/StarSurface.imageset, dipotong lingkaran dan diwarnai dari B-V. Jarak/nama/rasi/magnitude dari katalog, suhu estimasi; bukan foto per bintang. Koleksi menyimpan id, tanggal, latitude dan longitude dalam UserDefaults, tanpa verifikasi kamera atau sinkronisasi cloud.

## Batas implementasi

Posisi dihitung terhadap horizon geometris. Proper motion katalog, refraksi, skyline bangunan/pohon, lampu lokal dan awan per arah belum diterapkan. Visibilitas adalah heuristik, bukan probabilitas terkalibrasi. Laut dan lingkungan tetap asset dekoratif statis; warna siang-malam bersifat artistik. Ilustrasi rasi sudah ditampilkan secara kontekstual; urutan animasi pop-star/draw-line belum ada. Panduan kamera AR tersedia untuk Matahari dan bintang. Belum ada plate solving atau katalog planet interaktif. Garden menampilkan koleksi lokal sebagai galaksi dekoratif.

## Dokumentasi PDF

[Guide project, flow MVVM dan mapping asset](output/pdf/Celyx-Project-Guide.pdf) menjelaskan arsitektur, lifecycle, koordinat, mapping 360°, memasukkan asset ke Xcode, interaksi dan batas akurasi. Source generator: docs/generate_project_pdf.py (ReportLab + Pillow).

## Validasi

Unit test mencakup batas drag/zoom, reset, katalog dan pencarian, fokus kamera, basis koordinat renderer, round-trip proyeksi dan skala sudut di tepi layar, kompilasi pipeline GPU bintang, anggaran tekstur, siang-malam/lokasi aktual, persistensi koleksi serta input lokasi invalid. Snapshot ini lulus 11 unit test dan 2 UI test, termasuk tiga-anchor ilustrasi, fade/radius pandangan, resource 85 figure, serta toggle layer. Jalankan Test di Xcode.

Credits tersedia pada sheet Layers. Metadata lisensi asli dan pemberitahuan BSD disertakan dalam Resources. Katalog HYG tetap CC BY-SA 4.0, gambar rasi Stellarium/Johan Meuris Free Art License 1.3, metadata Stellarium CC BY-SA 4.0, dan garis d3-celestial BSD 3-Clause.

## Ilustrasi rasi bintang

`ConstellationFigure.load()` membaca 85 PNG dari `sky/figures` dan tiga anchor RA/Dec + pixel dari `figures.json`. `ConstellationFigureProjection` memproyeksikan anchor dengan basis astronomi dan kamera yang sama dengan bintang, lalu menghitung transformasi affine tiga titik. Tidak memakai angka HIP sebagai id katalog internal.

`ConstellationFiguresView` menampilkan maksimal dua rasi dengan pusat dalam radius 22° pandangan, opacity penuh sampai 12°, lalu memudar. Rasi harus punya bintang yang berpotensi terlihat, berada di atas horizon, dan tidak dalam detail sheet. Ilustrasi dipotong di ketinggian 9° agar tidak menutupi silhouette pulau dekoratif; mendekati batas itu opacity juga turun. Tampil mengikuti rotasi/zoom. Toggle **Ilustrasi rasi bintang** di Layers terpisah dari garis rasi dan aktif secara default.

PNG dibaca hanya untuk rasi yang terpilih dan cache dibatasi enam gambar (~6 MiB RGBA). Ilustrasi adalah overlay 2D affine berbasis tiga anchor, bukan mesh sferis penuh: ketiga anchor presisi, area lain adalah pendekatan proyeksi. Preview tersedia di ConstellationFiguresView.swift. Kredit Stellarium/Johan Meuris dan Free Art License 1.3 tetap disertakan.

## Temukan di Langit (kamera)

Tombol **Temukan di Langit** pada detail Matahari atau bintang membuka kamera ARKit. Aplikasi meminta izin kamera dan lokasi, memperoleh koordinat perangkat terbaru, lalu menghitung arah objek setiap detik. ARKit memakai `AROrientationTrackingConfiguration` dengan `gravityAndHeading` (utara sejati); posisi horizon east/north/up dikonversi menjadi east/up/south. Matriks pandang dan proyeksi kamera memperhitungkan orientasi layar dan kemiringan perangkat.

Panah menunjukkan arah putar/angkat/turunkan kamera, termasuk saat objek berada di belakang pengguna. Setelah jarak sudut ke arah kamera ≤3°, ilustrasi muncul di titik proyeksinya sendiri, bukan ditempelkan ke pusat layar. Objek di bawah horizon tidak ditampilkan seolah ada di depan kamera. Ini panduan posisi astronomi berbasis sensor, bukan deteksi objek di gambar kamera atau verifikasi presisi kompas. Gangguan magnet dan kalibrasi perangkat dapat menggeser arah.

Kamera tidak merekam/menyimpan foto atau video. Sesi AR dan lokasi berhenti saat keluar atau aplikasi tidak aktif; panorama berhenti merender selama kamera terbuka. Izin ditolak, lokasi belum tersedia, tracking terbatas, dan perangkat/Simulator tanpa ARKit memiliki status tersendiri. Panduan ini mendukung objek yang sudah tersedia (Matahari dan katalog bintang); katalog planet belum ditambahkan. Validasi arah, roll, proyeksi dan transisi modal dilakukan dengan tes; akurasi kamera/kompas tetap perlu diuji di iPhone fisik.

## Pulau dan transisi zoom ke ruang angkasa

Tekstur sumber `islands-360.png` memiliki garis vertikal pada RGB yang makin terlihat ketika diterangkan untuk siang. Renderer sekarang memakai alpha sebagai mask garis pantai, dengan warna daratan kontinu dan tepi yang tetap difilter, sehingga tidak memperbesar pola garis sumber. File aset asli tidak diubah.

FOV kamera panorama dibatasi 6–100° (default 72°). `SkySceneState.spaceBlend` melakukan smoothstep dari FOV 35° ke 8°: langit biru memudar menjadi hampir hitam, pulau/laut/perahu dan pendar atmosfer Matahari menghilang, serta Milky Way lebih jelas jika lapisannya aktif. Ekstingsi dan awan hanya dikurangi untuk tampilan; posisi langit, waktu, estimasi pengamatan, dan aturan koleksi tidak berubah. Ukuran inti bintang dibatasi saat zoom dalam. Reset mengembalikan FOV dan atmosfer awal. Transisi ini adalah efek eksplorasi visual, bukan simulasi perpindahan lokasi fisik ke orbit.

## Transisi detail objek

Memilih bintang/Matahari dari panorama, pencarian atau Sekitar memulai penerbangan kamera selama sekitar 1 detik. Arah berputar melalui lintasan terpendek terlebih dahulu, lalu FOV mengecil hingga 8° (atau mempertahankan zoom yang sudah lebih dekat). Perubahan kamera ditulis setiap frame dengan CADisplayLink, quintic easing, dan interpolasi logaritmik FOV; `withAnimation` saja tidak menginterpolasi uniform Metal. Ilustrasi detail bintang tumbuh dan memudar pada titik proyeksi bintangnya sendiri. Matahari memakai cakram renderer yang sama selama zoom. Label dan rasi memudar bersama transisi.

Sheet detail tampil setelah kamera tiba. Menutup tombol atau swipe sheet mengembalikan zoom dan arah sebelum pemilihan, dengan urutan balik. Core Motion tidak mengubah kamera selama inspeksi/animasi; setelah selesai, tracking dimulai lagi dengan offset untuk mempertahankan pandangan. Beralih ke Temukan di Langit memulihkan panorama di balik kamera tanpa animasi yang bersaing. Reduce Motion melewati animasi penerbangan. Transisi dituntaskan saat aplikasi tidak aktif agar tidak berjalan kembali dari frame yang tertunda.

## Garden / Your Galaxy

Tombol sparkles kanan bawah membuka **Your Galaxy**. `Resources/galaxy/your-galaxy-1400.jpg` disalin utuh dari paket aset v7 milik project (Generated for this project / Free to use sesuai LICENSES.md). Aset menjadi tekstur cakram dalam adegan 3D; marker ikut transformasi ruang galaksi. Timeline 30 FPS memutar galaksi perlahan; drag mengubah rotasi dan pinch mengubah pembesaran. Gerakan otomatis berhenti saat Reduce Motion aktif, aplikasi tidak aktif, atau saat daftar/detail koleksi terbuka. Panorama Metal dan sensor halaman Langit dihentikan selama Garden terbuka.

Setiap record `collectedStars` memiliki marker yang bisa ditekan. Pemilihan menampilkan label dan kartu di bawah; kartu membuka detail catatan koleksi. Tombol buku membuka **Collection**, dengan pencarian, kartu biru untuk objek tersimpan dan kartu terkunci untuk contoh objek katalog yang belum dikoleksi. Memilih kartu koleksi kembali ke galaksi dan memutar marker terpilih ke area terlihat. Tanggal dan koordinat menggunakan record asli, tanpa nama kota atau koleksi contoh buatan. Matahari dan record lama dengan id katalog yang tidak lagi ditemukan tetap ditangani. Saat koleksi kosong, galaksi tetap terlihat disertai ajakan kembali menjelajah langit.

Layout Garden bersifat dekoratif, stabil berdasarkan id objek, bukan posisi langit nyata atau simulasi orbit fisik. Objek saat ini berasal dari katalog bintang dan Matahari; gambar Bulan, gerhana, maupun koleksi planet tambahan pada referensi tidak dimasukkan sebagai record yang belum pernah dikoleksi pengguna.

## Garden: kamera dan ruang 3D

Garden memakai SceneKit: cakram galaksi bertekstur aset asli, 5.200 partikel pada lengan spiral dengan ketebalan, dan 900 bintang di volume ruang depan. Kamera perspektif bergerak dari jarak 48 ke 11.8 unit selama masuk; posisi dan kedalaman partikel menghasilkan parallax. Drag memutar galaksi, pinch mengubah jarak kamera. Marker koleksi dan label merupakan node dalam ruang yang sama. Putaran tetap 0.06 radian/detik, dengan kontrol jeda dan dukungan Reduce Motion.

Transisi tidak membesarkan NavigationStack atau toolbar. Kamera panorama mengarah ke atas dan mempersempit FOV lebih dahulu, kemudian kamera 3D bergerak mendekat. Peralihan render hanya singkat pada tahap penyerahan kamera. Saat kembali, perjalanan dibalik dan pose Langit dipulihkan. Pembungkus clip/scale seluruh halaman dihapus agar panorama kembali meluas di belakang status bar dan home indicator. Renderer Garden dijeda saat halaman koleksi/detail terbuka atau aplikasi tidak aktif.

## Kamera Bintang: anotasi titik cahaya

Tombol kamera di kiri bawah beranda membuka **Kamera Bintang**. Preview ARKit berbagi lifecycle kamera/lokasi dengan panduan target, tetapi mode ini tidak menempelkan ilustrasi atau label hanya berdasarkan posisi katalog. Kamera mendeteksi sumber luminansi kecil berkontras tinggi pada gambar Y 8-bit sekitar 5 kali/detik, menolak sumber melebar, piksel tunggal dan noise padat. Normalized image coordinates dipetakan ke viewport memakai displayTransform ARFrame, termasuk rotasi dan aspect-fill.

Titik cahaya dicocokkan dengan prediksi katalog di atas 5° horizon pada langit malam. Kandidat harus memiliki kecocokan lokal yang tidak ambigu dan stabil selama tiga pemindaian. Kotak hijau 5–14 pt mengikuti ukuran sumber cahaya; label nama berukuran kecil dapat ditekan. Penanda yang kehilangan kecocokan disembunyikan, termasuk saat kamera bergerak cepat atau tracking tidak tersedia. Maksimal delapan label ditampilkan untuk menghindari tumpang tindih.

Ketuk nama untuk membuka detail dan Collect dengan aturan visibilitas/ketinggian yang sudah ada. Detail menggunakan lokasi perangkat terbaru; koleksi masuk ke Garden. Kamera tidak merekam video atau menyimpan frame. Ini prototipe pencocokan titik cahaya + sensor, bukan plate solving atau pengenal bintang yang terkalibrasi: noise, lampu dan kesalahan heading masih dapat menghasilkan salah cocok atau tidak ada label. Penyetelan pada iPhone fisik di bawah langit malam diperlukan. Implementasi ini hanya diperiksa dengan build, tanpa menjalankan tes unit/UI sesuai permintaan.

## Exposure dan zoom kamera bintang

Ikon slider pada Kamera Bintang membuka kontrol exposure 0…+3 EV dan zoom 1…5×, dibatasi kemampuan perangkat. Pengaturan menggunakan `AROrientationTrackingConfiguration.configurableCaptureDeviceForPrimaryCamera`, bukan filter brightness pada preview. Zoom ditampilkan relatif terhadap zoom kamera saat sesi dimulai. Perangkat yang tidak menyediakan capture device untuk ARKit menampilkan kontrol nonaktif dengan penjelasan, tanpa mengubah kamera lain yang tidak digunakan sesi.

Pencocokan titik cahaya dikosongkan dan ditahan sekitar 0.8 detik setelah perubahan agar exposure/intrinsics baru stabil. Batas ukuran sumber cahaya pada detektor menyesuaikan zoom. Saat keluar atau sesi dijeda, exposure dan zoom kamera dikembalikan ke pengaturan sebelumnya. Ini tetap bergantung pada sensitivitas sensor; menambah EV tidak menjamin bintang terlihat, dan dapat meningkatkan noise. Hanya build dijalankan, tanpa tes unit/UI.

## Kontrol kamera langsung dan low-light

Kamera Bintang memilih format kamera utama wide 30 fps bila disediakan konfigurasi ARKit, supaya tersedia anggaran exposure per frame yang lebih panjang dibanding 60 fps. Mode auto exposure, continuous autofocus, pembatasan fokus jauh dan low-light boost diaktifkan hanya jika didukung; pengaturan kamera awal dipulihkan saat keluar. Tidak ada klaim bahwa pipeline ARKit identik dengan pemrosesan Camera iPhone.

Kontrol tidak lagi tersembunyi dalam popover: pinch melakukan zoom kamera, tombol 1×/2×/3×/6× muncul sesuai rentang perangkat, dan tahan tombol zoom membuka slider. Pemilihan preset memakai ramp zoom, sedangkan pinch mengikuti jari. Maksimum zoom relatif hingga 10× bila didukung; angka tersebut tidak menjanjikan pergantian lensa/zoom optik seperti kamera bawaan.

Tap preview mengatur titik autofocus dan auto exposure, dengan kotak kuning dan ikon matahari yang bisa digeser atas/bawah untuk exposure negatif maupun positif (hingga ±3 EV sesuai perangkat). Tahan preview menunggu fokus lalu mengunci AE/AF; tap lagi melepaskan lock. Kontrol ± di toolbar membuka exposure ruler langsung, dan menu menyediakan reset. Penanda identifikasi bintang tetap kotak hijau kecil. Verifikasi hanya melalui build, tanpa tes unit/UI; kualitas low-light dan perilaku kamera perlu dibandingkan pada iPhone fisik.

## Deteksi redup, penanda arah, dan kalibrasi gyro

Detektor titik cahaya kini memakai median lokal dan estimasi noise (MAD), bukan ambang luminansi absolut 130. Titik redup berkontras lokal tetap dapat menjadi kandidat. Sumber cahaya dilacak beberapa frame dalam arah ruang kamera; titik stabil yang belum cocok namanya diberi penanda putih “Titik cahaya”, sedangkan kecocokan katalog tetap hijau. Dengan demikian deteksi optik tidak lagi disamakan dengan keberhasilan identifikasi. Nama tidak dipaksakan untuk satu titik yang mungkin berupa planet, lampu, atau bintang di luar toleransi heading. Pencocokan memakai heading yang terbaca, toleransi sudut berbasis proyeksi, dan penolakan kandidat ambigu. Ketuk penanda putih untuk bantuan kalibrasi ulang arah.

Temukan di Langit kini hanya menampilkan ceklis kecil dan nama saat arah sesuai; tidak menempelkan ilustrasi planet/bintang pada kamera. Penanda tersebut berarti arah perkiraan sudah cocok, bukan konfirmasi objek terlihat menembus gedung atau awan.

Beranda dimulai dengan Sentuh dan memiliki pemilih Sentuh/Gyro. Setiap aktivasi gyro memulai kalibrasi ulang, menunggu GPS perangkat terbaru, heading true north dengan akurasi ≤8°, akurasi magnetometer medium/high, serta bacaan stabil setidaknya 1.2 detik. Tidak ada fallback ke arah relatif. Jika kualitas sensor memburuk, tracking ditahan dan kalibrasi muncul kembali. UI memperlihatkan progres, petunjuk gerakan angka 8, ulangi, dan kembali ke Sentuh. Manual coordinates dinonaktifkan pada mode Gyro. Kalibrasi kompas ini tetap memiliki galat sensor dan bukan kalibrasi astrometri presisi piksel.

Drag/pinch panorama hanya diterima pada Sentuh; sensor dihentikan pada mode tersebut. Di Gyro, pandangan berasal langsung dari orientasi kamera belakang terhadap utara sejati, tanpa offset dari drag atau posisi sebelumnya. Pergantian mode menghapus asal drag/zoom dan tidak mempertahankan offset. Pemeriksaan perubahan ini dilakukan dengan build saja, tanpa tes unit/UI sesuai permintaan.

### Panduan kalibrasi gyro

Kalibrasi menampilkan tahap lokasi, kompas, dan penahanan ponsel, dengan animasi jalur ∞ saat kompas membutuhkan gerakan. Akuisisi utara sejati menerima akurasi kompas sampai ±25° dan membutuhkan 1,2 detik dengan gerakan rotasi rendah. GPS awal menerima akurasi sampai 5 km untuk menghindari kebuntuan pada lokasi perkiraan. Bacaan magnetometer tidak lagi menjadi syarat kedua yang memblokir bacaan kompas valid. Setelah aktif, kualitas kompas ditampilkan di beranda; gangguan singkat tidak mengunci gyro, sedangkan arah tidak valid atau akurasi di atas ±45° selama 5 detik memicu kalibrasi ulang. Mode Sentuh dan Gyro tetap terpisah. Validasi build simulator; akurasi sensor membutuhkan pemeriksaan di perangkat fisik.

### Camera collection and sky notes

Sky Camera labels each observed source with a single nearby catalog guess; `≈` marks the angular fallback. Sun and Moon candidates use their live astronomical positions, and a separate compact-disc pass handles sources larger than a star point. Daytime no longer disables camera detection. Naming is still compass-assisted, not plate solving.

Camera Collect ignores cloud forecasts, atmospheric visibility estimates, and altitude thresholds. It captures the current camera frame without app overlays, crops it to the preview aspect ratio, and opens a journal draft. **Save Your Star** writes a JPEG under Application Support/StarJournal and stores the note, timestamp, coordinates, and identification hint with the collection record. Failed capture/save operations leave the draft unsaved and show a retry message. Existing collection records decode without photo fields; saved photo notes can be reopened from Your Galaxy or the camera detail. The map’s collection action opens the camera instead of silently saving a forecast-only record.

App copy, permission descriptions, and displayed dates use English. Build verified on the iOS Simulator target; no unit or UI tests run. Live detection, camera image orientation, and sensor accuracy need a physical iPhone check.

### Gyro zoom and initial virtual stars

Pinch zoom is available in Touch and Gyro after calibration. Gyro still controls azimuth/altitude, and dragging remains Touch-only. The virtual map starts with a magnitude limit of 3.8–4.2 and reveals stars up to magnitude 6.5 as the field of view narrows. Cloud forecasts no longer suppress the virtual star layer, and its extinction is capped at 0.12; physical visibility estimates and camera detection are unchanged. Labels and Metal points use the same virtual extinction formula.

### Tap-time camera photo

Tapping a named camera marker now immediately freezes the camera frame, timestamp, and observer location into an in-memory draft. The selected source’s tracked world direction is reprojected into that frame and a small gold ring is rendered around its image position; the source itself remains unobscured. Collect uses this draft instead of capturing another frame later. The marked image is saved with the note and is released on sheet dismissal if unsaved. Capture failure stays in the camera for a retry.

### Brightness-aware camera matching

Camera matching now uses one ranking path for both close and offset candidates. The five naked-eye planets (Mercury, Venus, Mars, Jupiter, Saturn) join stars, Sun, and Moon using Astronomy Engine positions and date-dependent visual magnitudes. Candidate direction is limited to a 6–12° window (`clamp(headingAccuracy × 0.75, 6, 12)`, default heading accuracy 10°); reported compass accuracy worse than ±25° suppresses naming. The heuristic magnitude ceiling is `3.5 + min(1.5, 0.5 × log2(zoom))`, about 3.5 at 1×, 4.29 at 3×, and 4.79 at 6×. It is a prior for this phone-camera flow, not an estimate of actual limiting magnitude from image pixels.

Lower scores win: angular separation in degrees + `0.9 × max(0, magnitude−1)` + `0.8 × max(0, magnitude−3)` − `min(1.5, 0.3 × max(0, −magnitude))`. Large-disc detections add 1.5 to non-Sun/Moon candidates; point detections do not match the Sun/Moon farther than 3°. Candidate score gaps below 0.75 are left unnamed. The same identity must persist for two detector updates, with at least three optical hits, before naming. Every displayed match retains ≈ and can still be a mistaken identity; the app does not do plate solving. No unit/UI tests run; simulator build only.

### Faint-light tracking recovery

The zoom-based magnitude threshold is now a preference, not a hard candidate cutoff: entries through magnitude 5.5 remain eligible, with an added score penalty of 1.5 per magnitude beyond the preferred brightness range. Optical detection and unnamed markers remain independent of catalogue ranking and compass quality. The compact-source detector uses a 3σ global peak prefilter and 4σ local contrast check, while retaining connected-component size/shape rejection. Optical tracks survive missed analysis passes for up to 0.65 seconds; markers expire after 0.4 seconds without a fresh detection. An unnamed marker needs two optical hits; names still require three optical hits and a repeated candidate. Candidate confirmations advance only when the source was actually observed in that pass. Status copy distinguishes camera adjustments, a source awaiting stability, and a detected source awaiting a name. Simulator build passed; no unit/UI tests run. Live recovery still needs an iPhone check.
