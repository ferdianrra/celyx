#
#  generate_project_pdf.py
#  celyx
#
#  Created by Ferdiansyah Annora on 02/11/26.
#
"""Regenerate the Indonesian project guide from the repository root."""
from pathlib import Path
from io import BytesIO
import math, random
from reportlab.pdfgen import canvas
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import Paragraph, Table, TableStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.utils import ImageReader
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'output/pdf/Celyx-Project-Guide.pdf'
TMP = ROOT/'tmp/pdfs'; TMP.mkdir(parents=True,exist_ok=True)
FONT = Path('/System/Library/Fonts/Supplemental')
pdfmetrics.registerFont(TTFont('Body',str(FONT/'Arial.ttf')))
pdfmetrics.registerFont(TTFont('Bold',str(FONT/'Arial Bold.ttf')))
pdfmetrics.registerFont(TTFont('Italic',str(FONT/'Arial Italic.ttf')))
pdfmetrics.registerFontFamily('Body',normal='Body',bold='Bold',italic='Italic',boldItalic='Bold')
W,H=A4; M=46; CW=W-2*M
NAVY=colors.HexColor('#121831'); BLUE=colors.HexColor('#3458D9'); CYAN=colors.HexColor('#24B5BB')
INK=colors.HexColor('#242C43'); MUTED=colors.HexColor('#68728B'); LIGHT=colors.HexColor('#EFF3FA'); WHITE=colors.white
styles={
 'body':ParagraphStyle('body',fontName='Body',fontSize=10.3,leading=15.6,textColor=INK,spaceAfter=9),
 'small':ParagraphStyle('small',fontName='Body',fontSize=8.6,leading=12.7,textColor=MUTED),
 'tiny':ParagraphStyle('tiny',fontName='Body',fontSize=7.6,leading=10.3,textColor=MUTED),
 'heading':ParagraphStyle('heading',fontName='Bold',fontSize=13.5,leading=18,textColor=NAVY),
 'white':ParagraphStyle('white',fontName='Body',fontSize=11.5,leading=17,textColor=WHITE),
 'code':ParagraphStyle('code',fontName='Body',fontSize=9.1,leading=14,textColor=BLUE),
}
c=canvas.Canvas(str(OUT),pagesize=A4)
c.setTitle('Celyx | Dokumentasi Project, Flow MVVM & Mapping Asset')
c.setAuthor('Ferdiansyah Annora')
c.setSubject('Panduan implementasi untuk tim: SwiftUI, Metal, astronomi, GPS, asset dan visibilitas')
page_no=0

def para(text,x,y,width=CW,style='body'):
 p=Paragraph(text,styles[style]); _,height=p.wrap(width,H)
 if y-height<48: raise ValueError(f'Page {page_no}: text overflows at {y}: {text[:65]}')
 p.drawOn(c,x,y-height); return y-height

def heading(text,y): return para(text,M,y,style='heading')-9

def page(section,title,subtitle=None):
 global page_no
 if page_no: c.showPage()
 page_no+=1
 c.setFillColor(WHITE); c.rect(0,0,W,H,fill=1,stroke=0)
 c.setFillColor(BLUE); c.setFont('Bold',8); c.drawString(M,H-35,'CELYX / ENGINEERING GUIDE')
 c.setFillColor(MUTED);c.setFont('Body',8);c.drawRightString(W-M,H-35,section.upper())
 c.setStrokeColor(LIGHT);c.line(M,H-45,W-M,H-45)
 c.setFillColor(NAVY);c.setFont('Bold',25);c.drawString(M,H-89,title)
 y=H-108
 if subtitle: y=para(subtitle,M,y,style='small')-17
 c.setStrokeColor(LIGHT);c.line(M,40,W-M,40)
 c.setFont('Body',7.6);c.setFillColor(MUTED)
 c.drawString(M,27,'Ferdiansyah Annora  |  Snapshot implementasi 02 Nov 2026')
 c.drawRightString(W-M,27,f'{page_no:02d} / 11')
 return y

def box(text,x,y,width,height,bg=LIGHT,title=None):
 c.setFillColor(bg); c.roundRect(x,y-height,width,height,11,fill=1,stroke=0)
 top=y-14
 if title: top=para(title,x+14,top,width-28,'heading')-7
 return para(text,x+14,top,width-28,'small')

def table(rows,widths,y):
 data=[]
 for row_index,row in enumerate(rows):
  style=ParagraphStyle('cell',parent=styles['small'],fontName='Bold' if row_index==0 else 'Body',textColor=WHITE if row_index==0 else INK,fontSize=8.7,leading=12.5)
  data.append([Paragraph(str(value),style) for value in row])
 t=Table(data,colWidths=widths,hAlign='LEFT')
 t.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),NAVY),('VALIGN',(0,0),(-1,-1),'TOP'),('LEFTPADDING',(0,0),(-1,-1),10),('RIGHTPADDING',(0,0),(-1,-1),10),('TOPPADDING',(0,0),(-1,-1),9),('BOTTOMPADDING',(0,0),(-1,-1),9),('ROWBACKGROUNDS',(0,1),(-1,-1),[WHITE,LIGHT]),('LINEBELOW',(0,0),(-1,0),1,NAVY)]))
 _,height=t.wrap(CW,H)
 if y-height<52: raise ValueError(f'Page {page_no}: table overflow {y-height}')
 t.drawOn(c,M,y-height);return y-height-18

def arrow(x1,y1,x2,y2,color=BLUE):
 c.setStrokeColor(color);c.setFillColor(color);c.setLineWidth(1.2);c.line(x1,y1,x2,y2)
 a=math.atan2(y2-y1,x2-x1);p=c.beginPath();p.moveTo(x2,y2)
 p.lineTo(x2-6*math.cos(a-.4),y2-6*math.sin(a-.4));p.lineTo(x2-6*math.cos(a+.4),y2-6*math.sin(a+.4));p.close();c.drawPath(p,fill=1,stroke=0)

def node(title,sub,x,y,width,height=66):
 c.setFillColor(LIGHT);c.roundRect(x,y-height,width,height,10,fill=1,stroke=0)
 para(title,x+12,y-12,width-24,'heading');para(sub,x+12,y-34,width-24,'tiny')

def image(path,x,y,width,height):
 im=Image.open(path).convert('RGBA');im.thumbnail((1600,1600))
 ratio=min(width/im.width,height/im.height);rw,rh=im.width*ratio,im.height*ratio
 c.drawImage(ImageReader(im),x+(width-rw)/2,y-rh,width=rw,height=rh,mask='auto')
 return y-rh

def step(n,title,body,y):
 c.setFillColor(BLUE);c.circle(M+13,y-13,13,fill=1,stroke=0)
 c.setFillColor(WHITE);c.setFont('Bold',10);c.drawCentredString(M+13,y-17,str(n))
 top=para(title,M+39,y,CW-39,'heading')-5
 return para(body,M+39,top,CW-39)-20

# 1 --------------------------------------------------------------------------
y=page('Mulai di sini','Celyx, dari asset ke langit', 'Dokumentasi project untuk membantu tim memahami alur kerja, membagi tanggung jawab, dan menambah asset dengan aman.')
c.setFillColor(NAVY);c.roundRect(M,y-205,CW,205,16,fill=1,stroke=0)
rng=random.Random(42)
for _ in range(105):
 x=M+rng.uniform(12,CW-12);yy=y-rng.uniform(10,195);c.setFillColor(colors.Color(.6,.7,1,alpha=rng.uniform(.2,.7)));c.circle(x,yy,rng.uniform(.3,1),fill=1,stroke=0)
para('Peta langit interaktif<br/><b>SwiftUI + MVVM + Metal</b>',M+23,y-30,CW-46,'white')
para('GPS + waktu aktual menentukan posisi.<br/>Data katalog menentukan identitas.<br/>Model atmosfer membantu memperkirakan visibilitas.',M+23,y-108,CW-46,'white')
y-=230
y=heading('Yang sudah ada di snapshot ini',y)
y=para('Panorama 360°, drag dan zoom, nama bintang dekat tengah layar, detail bintang, koleksi lokal, daftar di atas horizon, GPS/manual, siang-malam dari posisi Matahari, serta opsi awan dan aerosol online.',M,y)-15
y=table([['Bagian panduan','Halaman'],['Arsitektur & flow pengguna','2-3'],['Koordinat astronomi & mapping 360°','4-6'],['Memasukkan asset & interaksi bintang','7-8'],['Estimasi visibilitas, validasi & rencana tim','9-10'],['Sumber dan lisensi','11']],[CW-85,85],y)
box('Dokumen ini menjelaskan kode yang ada, bukan janji akurasi hasil pengamatan. Foto lingkungan bersifat dekoratif; posisi objek dihitung, sedangkan kondisi terlihat tetap estimasi.',M,y,CW,70)

# 2 --------------------------------------------------------------------------
y=page('Arsitektur','Siapa mengerjakan apa?', 'MVVM memisahkan tampilan, state interaksi, perhitungan, dan akses sensor/API.')
node('Service','Lokasi, waktu, astronomi, atmosfer',M,y,205)
node('Asset + katalog','Gambar, stars.json, rasi, lisensi',W-M-205,y,205)
arrow(M+103,y-66,W/2-30,y-97);arrow(W-M-103,y-66,W/2+30,y-97)
node('HomeViewModel','Koordinator state, observasi, pilihan bintang',W/2-150,y-97,300,69)
arrow(W/2-70,y-166,M+108,y-201);arrow(W/2+70,y-166,W-M-108,y-201)
node('SwiftUI Views','HUD, label, list, detail, Collect',M,y-201,215)
node('Metal Renderer','Background, GPU stars, foreground',W-M-215,y-201,215)
y-=292
y=table([['Lokasi kode','Tanggung jawab'],['Features/Home/Models','SkySceneState, CameraProjection, CatalogStar, ObserverLocation, StarObservation, VisibilityEstimator.'],['Features/Home/ViewModels','HomeViewModel menerima event, memperbarui state, dan menyimpan koleksi.'],['Features/Home/Services','AstronomyService, LocationService, MotionService, AtmosphereService.'],['Features/Home/Views','HomeView, HomeSheetView, StarLabelsView, StarDetailView, StarPortraitView.'],['Features/Home/Rendering','PanoramaView.swift dan PanoramaShader.txt. Adaptasi MTKView serta pipeline Metal.'],['Vendor/AstronomyEngine','Sumber C upstream yang dipin, header, dan lisensi MIT.']],[168,CW-168],y)
para('<b>Aturan kolaborasi:</b> View mengirim aksi ke ViewModel. Perhitungan astronomi tidak ditulis di body View. Renderer menerima state; ia tidak membuka sheet atau menulis koleksi.',M,y,style='small')

# 3 --------------------------------------------------------------------------
y=page('Lifecycle','Flow saat app dibuka', 'Tidak ada fallback diam-diam ke Jakarta jika koordinat belum tersedia.')
y=step(1,'Baca asset dan state lokal','Katalog dan nama rasi dibuka dari bundle. Koleksi sebelumnya dibaca dari UserDefaults. Renderer menyiapkan tekstur dan vertex buffer satu kali.',y)
y=step(2,'Minta lokasi perangkat','HomeViewModel.resume() memulai layanan lokasi. Izin ditolak atau GPS belum ada: tampilkan status dan pilihan koordinat manual. Jangan tampilkan langit sebagai lokasi aktual sebelum ada koordinat.',y)
y=step(3,'Hitung satu snapshot langit','Waktu UTC + latitude/longitude/elevasi masuk ke AstronomyService. Hasilnya: basis J2000 ke horizon, arah Matahari/Bulan, dan fraksi iluminasi Bulan.',y)
y=step(4,'Perbarui tampilan dan estimasi','Basis yang sama dipakai GPU, label, daftar dan fokus detail. Observasi diperbarui setiap 5 detik; drag/sensor cukup mengubah kamera tanpa menghitung ulang ephemeris per frame.',y)
y=step(5,'Online conditions bersifat pilihan','Jika toggle aktif, koordinat dikirim ke Open-Meteo. Awan dan aerosol diminta paralel, timeout 15 detik, refresh paling sering tiap 30 menit atau saat lokasi berubah.',y)
y=step(6,'App tidak aktif','suspend() menghentikan sensor, GPS, clock task dan request cuaca. MTKView di-pause. Reduce Motion juga mematikan goyangan perahu dan memakai render saat state berubah.',y)
box('Preview Xcode dan UI test memakai fixture koordinat/waktu yang jelas. Mode pemakaian normal memakai Date() dan GPS, atau koordinat manual yang dipilih pengguna.',M,y,CW,65)

# 4 --------------------------------------------------------------------------
y=page('Astronomi','Dari katalog ke arah langit', 'RA/Dec katalog bukan koordinat piksel dan bukan posisi relatif terhadap utara lokal.')
y=para('<b>Input:</b> stars.json menyimpan RA dan Dec dalam derajat, epoch J2000. Posisi pengamat dan waktu menentukan cara koordinat itu diputar ke horizon lokal.',M,y)-15
node('J2000 / EQJ','x: RA 0h  |  y: RA 6h  |  z: kutub utara',M,y,CW)
arrow(W/2,y-66,W/2,y-95)
node('Astronomy_Rotation_EQJ_HOR','Waktu UTC + observer(latitude, longitude, height)',M,y-95,CW)
arrow(W/2,y-161,W/2,y-190)
node('Horizon aplikasi','x = east  |  y = north  |  z = up',M,y-190,CW)
y-=281
y=heading('Konvensi yang harus konsisten',y)
y=para('Astronomy Engine mengembalikan HOR dengan x = north, y = west, z = up. Service mengubahnya menjadi <b>(-HOR.y, HOR.x, HOR.z)</b>. Jangan menukar tanda di shader atau label secara terpisah.',M,y)-12
y=table([['Nilai','Rumus / penggunaan'],['Vektor katalog','e = (cos(dec)cos(ra), cos(dec)sin(ra), sin(dec))'],['Vektor dunia','d = basis * e'],['Ketinggian','altitude = asin(d.z); horizon geometris = 0°'],['Arah kompas','azimuth = atan2(d.x, d.y); bungkus menjadi 0-360°'],['GPU dan label','Gunakan basis snapshot yang sama. Basis tidak boleh dikurasi agar galaksi selalu di depan perahu.']],[123,CW-123],y)
para('Rotasi memasukkan precession/nutation. Proper motion tidak tersedia pada asset ini; refraksi atmosfer tidak diterapkan pada posisi geometris. Sensor arah ponsel dan kalibrasi harus diuji terpisah dari ketepatan perhitungan.',M,y,style='small')

# 5 --------------------------------------------------------------------------
y=page('Inventaris asset','Lapisan yang membentuk Home', 'Urutan visual dijaga agar bintang tertutup pulau, laut, dan perahu secara benar.')
y=table([['Asset / sumber','Ukuran sumber','Cara dipakai'],['environment/sky-gradient-360.jpg','8192 x 4096','Backdrop malam; tekstur kerja 1024 px lebar.'],['sky/milky-way-radec-4096.jpg','4096 x 2048','Sample J2000 RA/Dec; additive dan diredam saat langit terang/kota.'],['sky/stars.json','3.248 entri aktual','Vertex buffer 3D, satu draw call point sprites; bukan foto panorama.'],['sky/constellations.json','88 entri','Garis antar id katalog; dibake 2048 x 1024.'],['environment/islands-360.png','8192 x 4096, alpha','Silhouette horizon; tekstur kerja 2048 px lebar.'],['environment/sea-360.png','8192 x 4096, alpha','Laut statis; tekstur kerja 4096 px lebar.'],['environment/boat-360-night.png<br/>environment/boat-360.png','4096 x 2048, alpha','Versi malam/siang dicampur menurut Matahari; masing-masing kerja 2048 px.'],['Assets.xcassets/StarSurface','PNG referensi pemilik','Ilustrasi detail, diwarnai lewat indeks B-V. Bukan foto tiap bintang.']],[212,97,CW-309],y)
y=heading('Tiga tahap GPU dalam satu render encoder',y)
node('1. Background','Gradient + Milky Way + garis',M,y,158,62)
node('2. Bintang','Point sprites dari katalog',M+173,y,158,62)
node('3. Foreground','Pulau + laut + perahu',M+346,y,CW-346,62)
arrow(M+158,y-31,M+173,y-31);arrow(M+331,y-31,M+346,y-31)
y-=83
para('Catatan inventaris: panduan asset lama menyebut 3.247 bintang; file stars.json yang diberikan berisi 3.248 entri. Implementasi dan tes mengikuti isi file aktual.',M,y,style='small')

# 6 --------------------------------------------------------------------------
y=page('Mapping 360°','Cara membaca gambar panorama', 'Equirectangular berarti seluruh bola dipetakan menjadi persegi panjang berasio 2:1.')
img_y=y-12; iw=CW; ih=CW/2
c.setFillColor(NAVY);c.rect(M,img_y-ih,iw,ih,fill=1,stroke=0)
image(ROOT/'celyx/Resources/environment/environment-360-preview.jpg',M,img_y,iw,ih)
c.setStrokeColor(CYAN);c.setLineWidth(1);c.line(M,img_y-ih/2,M+iw,img_y-ih/2);c.line(M+iw/2,img_y,M+iw/2,img_y-ih)
for label,xx,yy in [('ZENITH',M+8,img_y-17),('HORIZON',M+8,img_y-ih/2+7),('NADIR',M+8,img_y-ih+10),('NORTH / u = 0.5',M+iw/2+8,img_y-30)]:
 c.setFont('Bold',8);c.setFillColor(WHITE);c.drawString(xx,yy,label)
y=img_y-ih-18
y=para('Garis cyan menunjukkan konvensi pada <b>environment</b>: kolom tengah menghadap utara; horizon ada di tengah tinggi gambar; tepi kiri dan kanan bertemu di arah selatan. Preview gabungan ini hanya ilustrasi; renderer membaca layer terpisah.',M,y,style='small')-18
y=table([['Environment','Milky Way / RA-Dec'],['u = atan2(d.x, d.y)/(2*pi) + 0.5<br/>v = 0.5 - asin(d.z)/pi','e = transpose(basis) * d<br/>u = atan2(e.y,e.x)/(2*pi), dibungkus 0-1<br/>v = acos(e.z)/pi'],['North: u=0.5; horizon: v=0.5','RA 0h ada di tepi kiri. Kutub utara langit di baris atas. Tidak sama dengan utara lokal.']],[CW/2,CW/2],y)
y=heading('Kenapa tidak sekadar menggeser gambar 2D?',y)
y=para('Setiap piksel diubah menjadi ray 3D, lalu disample dari panorama. Kamera memakai proyeksi stereografik yang menjaga bentuk lokal saat melihat ke atas. Bintang katalog digambar sebagai lingkaran dalam koordinat layar agar tidak melonjong.',M,y)-8
para('Sampler membungkus s/u dan menjepit t/v. Foreground memakai alpha premultiplied. Derivatif tekstur dihitung sebelum branch horizon agar mipmap tidak memunculkan garis putus-putus di tepi laut.',M,y,style='small')

# 7 --------------------------------------------------------------------------
y=page('Tutorial asset','Menambah atau mengganti gambar', 'Alur praktis di project Xcode ini, tanpa ketergantungan pada folder Downloads anggota tim.')
y=step(1,'Pilih tempat yang tepat','Panorama/data mentah: celyx/Resources/environment atau Resources/sky. Ilustrasi UI bernama: Assets.xcassets. Gambar perahu harus punya transparansi dan rasio 2:1 yang sesuai konvensi.',y)
y=step(2,'Masukkan ke project dan target','Folder celyx memakai sinkronisasi folder pada project.xcproj. Simpan file di dalam folder itu dan pastikan target celyx memasukkannya saat build. Jangan menambah referensi kedua untuk file yang sama.',y)
y=step(3,'Jaga nama unik dan ekstensi','SkyAssets.url(name, extension:) mencari bundle, termasuk bundle yang diratakan Xcode. Dua file dengan basename identik bisa bertabrakan. Gunakan nama deskriptif dan perhatikan huruf besar/kecil.',y)
y=step(4,'Daftarkan ke renderer atau View','Panorama baru: tambah load(name, ext, width:) di PanoramaRenderer, texture index dan binding shader yang sama. Ilustrasi UI: buat Image Set, isi PNG, lalu akses Image("NamaAsset").',y)
y=step(5,'Uji orientasi dan transparansi','Cek utara, timur, selatan, zenith dan horizon. Putar 360° melewati seam kiri/kanan. Cek warna RGBA8 dan tepi alpha di latar terang/gelap, serta Preview dan simulator.',y)
y=step(6,'Perbarui kredit dan anggaran memori','Simpan lisensi bersama asset. Ukuran decode GPU berbeda dari ukuran PNG/JPG di disk. Tes saat ini membatasi alokasi tekstur <=160 MiB; gambar sumber tetap utuh.',y)
box('Contoh nyata: StarSurface.imageset berisi star-surface.png + Contents.json. StarPortraitView membaca Image("StarSurface"), menghilangkan saturasi, memberi warna dari B-V, dan memotongnya menjadi lingkaran.',M,y,CW,70)

# 8 --------------------------------------------------------------------------
y=page('Interaksi','Nama, detail, lalu Collect', 'Satu id katalog menghubungkan titik GPU, label, daftar, detail, dan koleksi.')
shot=ROOT/'docs/images/home-current.png'
if shot.exists(): image(shot,M,y,185,403)
right=M+207; ww=CW-207
node('Label dekat pusat','Nama umum, berpotensi terlihat, dalam 22° dari kamera. Maksimal 5 label, jarak antarlabelling >=66 pt.',right,y,ww,92)
arrow(right+ww/2,y-92,right+ww/2,y-114)
node('Tap titik / list','showDetail(star) menyimpan selectedStar, memusatkan kamera dan membuka sheet detail.',right,y-114,ww,88)
arrow(right+ww/2,y-202,right+ww/2,y-224)
node('Collect star','Aktif hanya jika berpotensi terlihat dan altitude >=15°. Id yang sama tidak diduplikasi.',right,y-224,ww,88)
arrow(right+ww/2,y-312,right+ww/2,y-334)
node('UserDefaults','Simpan id, tanggal, latitude dan longitude. Lokal di perangkat; belum sinkronisasi akun.',right,y-334,ww,78)
y-=432
y=heading('Data di detail diambil dari mana?',y)
y=table([['Elemen','Sumber'],['Nama, rasi, magnitude, jarak','HYG + nama rasi dari constellations.json. Tidak mengarang biografi bintang.'],['Warna dan suhu','Indeks B-V: warna ilustratif dan pendekatan suhu. Bukan pengukuran suhu live.'],['Altitude, azimuth, arah kompas','Snapshot astronomi yang sama dengan renderer.'],['Ilustrasi permukaan','Asset PNG referensi yang sama untuk semua bintang; diberi warna dari katalog.']],[157,CW-157],y)
para('Screenshot di kiri berasal dari UI test dengan koordinat manual Jakarta dan waktu fixture 2 Nov 2026, 22.30 WIB. Itu bukan bukti lokasi GPS perangkat. Tombol Sekitar membuka seluruh katalog di atas horizon, bukan hanya yang terlihat mata.',M,y,style='small')

# 9 --------------------------------------------------------------------------
y=page('Visibilitas','Posisi tepat, terlihat belum pasti', 'Aplikasi ini masuk akal sebagai pemandu pengamatan dan koleksi pribadi; kualitas prediksinya perlu dikalibrasi.')
y=table([['Pertanyaan','Jawaban implementasi'],['Di mana bintangnya?','Dihitung dari koordinat katalog, waktu dan lokasi. Tidak bergantung pada AQI.'],['Di atas horizon?','Altitude geometris >0°. Belum memasukkan skyline bangunan/pohon atau refraksi.'],['Berpotensi terlihat?','Altitude >1°, Matahari <-6°, magnitude teredam di bawah limit dan awan model <75%.'],['Bisa Collect?','Berpotensi terlihat + altitude >=15°. Ini aturan produk, bukan bukti bintang terdeteksi.']],[147,CW-147],y)
y=heading('Model awal yang benar-benar ada di kode',y)
y=para('<b>Limit magnitude:</b> pilihan cahaya sekitar (kota 3, pinggiran 4, pedesaan 5, gelap 5.6), dikurangi efek senja dan Bulan. Ini parameter heuristik, belum hasil pemetaan polusi cahaya otomatis.',M,y)-9
y=para('<b>Magnitude setelah atmosfer:</b> m + k * max(airmass - 1, 0), dengan k = 0.15 + 1.086 * AOD. Bila AOD belum tersedia dipakai asumsi 0.14, dan UI tetap menulis data online tidak diketahui. Angka ini tidak menyatakan probabilitas terkalibrasi.',M,y)-9
y=para('<b>PM2.5:</b> ditampilkan sebagai konteks kualitas udara. PM2.5/AQI bukan ukuran polusi cahaya; model ini memakai AOD untuk haze atmosfer, sementara cahaya sekitar masih dipilih manual.',M,y)-16
box('Open-Meteo/CAMS adalah data model berskala wilayah, bukan sensor tepat di arah bintang. Data gagal, null, atau lebih dari 3 jam tidak dianggap sebagai pengukuran langit cerah. Awan per arah, adaptasi mata, lampu dekat, polusi cahaya terukur dan penghalang lokal belum dimodelkan.',M,y,CW,122,title='Unknown harus tetap unknown')
y-=144
para('<b>Prioritas akurasi berikutnya:</b> kalibrasi kompas pada bintang dikenal, peta sky brightness atau SQM, skyline lokal, dan validasi lapangan dengan data bintang yang benar-benar dilihat pengguna. Jangan menjanjikan persentase akurasi sebelum ada dataset evaluasi.',M,y,style='small')

# 10 -------------------------------------------------------------------------
y=page('Validasi & handoff','Menjalankan dan mengembangkan', 'Build dan tes simulator sudah dilakukan; evaluasi sensor dan performa fisik tetap terpisah.')
y=heading('Quick start tim',y)
y=para('1. Buka <b>celyx.xcodeproj</b>, pilih scheme celyx dan simulator iOS 27.2.<br/>2. Build/Run. Untuk perangkat fisik, sesuaikan Signing Team.<br/>3. Izinkan lokasi atau isi koordinat manual lewat dock Pengamatan.<br/>4. Geser panorama, cari bintang, buka detail dan daftar Sekitar.<br/>5. Aktifkan online conditions bila ingin memakai awan/AOD model.<br/>6. Jalankan Test di Xcode. Preview tersedia di setiap View.',M,y)-18
y=table([['Pemeriksaan','Status / cakupan'],['8 unit test','Drag/zoom/reset; katalog/fokus; basis live dan siang-malam; persistensi koleksi; lokasi invalid; proyeksi stereografik; shader GPU dan budget tekstur.'],['1 UI test','Home, drag/reset, melihat ke atas, layer grid, pencarian Sirius, detail/Collect dan daftar Sekitar. Fixture GPS/waktu sengaja deterministik.'],['API smoke check','Endpoint AOD/PM2.5 merespons saat diperiksa; cuaca sempat 503. Alur kegagalan tetap menampilkan unknown, bukan hasil palsu.'],['Belum diuji lapangan','Arah true north di iPhone, observasi mata, total memori dan FPS sustained pada beberapa perangkat. Target render 60 FPS bukan hasil benchmark perangkat.']],[134,CW-134],y)
y=heading('Pembagian tanggung jawab yang disarankan',y)
y=para('<b>UI:</b> HUD, label, list, detail dan accessibility.<br/><b>Rendering:</b> pipeline, mipmap, warna siang-malam, point sprites dan budget GPU.<br/><b>Astronomi/data:</b> koordinat, proper motion/refraksi, estimator dan cache API.<br/><b>Platform:</b> GPS, Core Motion, izin, persistence dan lifecycle.<br/><b>QA:</b> fixture waktu/lokasi, test otomatis, kalibrasi lapangan dan profil perangkat.',M,y)-12
para('Batas produk saat ini: lingkungan dekoratif dan laut statis; warna siang-malam masih artistik. Belum ada deteksi kamera/plate solving, foto per bintang, koleksi cloud, planet interaktif, atau validasi prediksi dengan observasi lapangan.',M,y,style='small')

# 11 -------------------------------------------------------------------------
y=page('Referensi','Sumber, lisensi, dan keputusan', 'Tautan berikut membantu tim memeriksa data, memperbarui dependensi, dan menyiapkan rilis.')
refs=[
 ('Astronomy Engine','https://github.com/cosinekitty/astronomy','Rotasi koordinat, Matahari dan Bulan. MIT; source dipin pada commit 865d3da7d8112bbc7911238052c6af4aaf877181. File upstream tidak diberi header project agar tetap utuh.'),
 ('Dokumentasi C / konvensi koordinat','https://github.com/cosinekitty/astronomy/blob/master/source/c/README.md','EQJ ke HOR dan vektor. Sasaran akurasi library tidak otomatis menjadi akurasi arah sensor atau prediksi visibilitas aplikasi.'),
 ('Open-Meteo Weather API','https://open-meteo.com/en/docs','Data cloud_cover. Bersifat model; tampilkan timestamp, unknown dan kegagalan.'),
 ('Open-Meteo Air Quality API','https://open-meteo.com/en/docs/air-quality-api','AOD 550 nm dan PM2.5 dari CAMS. Data model, bukan sensor setempat.'),
 ('Open-Meteo Terms','https://open-meteo.com/en/terms','Atribusi CC BY 4.0. Endpoint gratis ditujukan untuk non-komersial; evaluasi paket yang sesuai sebelum rilis komersial.'),
 ('DarkSky: light pollution','https://darksky.org/resources/what-is-light-pollution/','Polusi cahaya berasal dari cahaya buatan. Jangan memakai AQI sebagai penggantinya.'),
]
for title,url,note in refs:
 y=para(f'<b>{title}</b>',M,y,style='body')-2
 y=para(f'<link href="{url}" color="#3458D9">{url}</link>',M,y,style='small')-4
 y=para(note,M,y,style='small')-16

y=heading('Asset dan pemberitahuan yang disertakan',y)
y=para('HYG v3.8: CC BY-SA 4.0. Gambar rasi Stellarium/Johan Meuris: Free Art License 1.3. Metadata Stellarium: CC BY-SA 4.0. Garis d3-celestial: BSD 3-Clause. Simpan pemberitahuan lisensi asli bersama sumber; kredit runtime tersedia di sheet Layers.',M,y,style='small')-12
para('Acuan utama dokumentasi ini adalah source code pada snapshot project saat PDF dibuat. Jika struktur file atau aturan visibilitas berubah, perbarui guide, tes dan README bersama perubahan kodenya.',M,y,style='small')
c.save()
print(f'Created {OUT} ({page_no} pages)')
