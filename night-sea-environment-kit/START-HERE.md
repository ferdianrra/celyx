# Night Sea environment kit

Isinya scene langit malam di atas laut, lengkap sama pulau-pulaunya. Bintang, planet, Bulan, dan Milky Way-nya posisinya beneran, sesuai lokasi dan jam kamu. Kit ini cuma environment-nya aja, belum ada fitur app sama sekali.

## Mau lihat dulu
Buka **`night-sea-preview.html`** (double-click aja, jalan di browser, bisa offline). Geser buat lihat sekeliling, pinch atau scroll buat zoom. Di HP, tap sekali kalau mau lihat sekeliling pakai gerakan HP.

## Mau dioprek pakai Claude
Cara paling gampang, pilih salah satu:

**A. Claude Code (paling enak, Claude bisa langsung edit dan jalanin)**
1. Unzip folder ini, buka terminal di folder itu, ketik `claude`.
2. Claude otomatis baca `CLAUDE.md`, jadi langsung paham isinya.
3. Copy salah satu prompt dari `PROMPTS.md`, paste, selesai.

**B. claude.ai (lewat browser/app)**
1. Bikin Project baru, terus upload 4 file ini ke project knowledge: `CLAUDE.md`, `web/env.js`, `shader/environment.frag.glsl`, `web/index.html`.
   Jangan upload `stars.js`/`stars.json`, isinya cuma data bintang dan bikin penuh.
2. Copy prompt dari `PROMPTS.md`, paste di chat project itu.

## Isi folder
- `night-sea-preview.html`: semuanya dalam satu file, buat dilihat atau dikirim ke orang.
- `web/`: kode yang bisa dibaca dan diedit (`env.js` + `index.html`).
- `shader/environment.frag.glsl`: shader langit, pulau, dan laut.
- `data/`: data bintang + gambar Milky Way 4K.
- `tools/build.py`: abis ngedit, jalanin `python3 tools/build.py` biar file preview ikut ke-update.
- `CLAUDE.md`: penjelasan teknis buat Claude (atau buat kamu kalau penasaran).
- `PROMPTS.md`: prompt siap pakai.
- `LICENSES.md`: kredit yang wajib dicantumin kalau dipakai (data bintang HYG, CC BY-SA 4.0).
