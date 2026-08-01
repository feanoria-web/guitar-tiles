# Cloudflare R2 şarkı aktarımı kurulumu

## Mimari

- Firebase Realtime Database oda, oyuncu ve WebRTC sinyallemesini yönetir.
- Host şarkıyı 4 MB parçalar halinde Cloudflare R2'ye yalnızca bir kez yükler.
- Worker, istekteki Firebase ID tokenını mevcut odaya karşı doğrular.
- Sadece oda sahibi upload yapabilir; sadece odadaki oyuncular indirebilir.
- R2 kullanılamazsa oyun mevcut WebRTC aktarımına otomatik döner.

## 1. R2'yi etkinleştir

1. `https://dash.cloudflare.com/` adresinde oturum aç.
2. Sol menüden **Storage & databases > R2 Object Storage** bölümünü aç.
3. İstenirse R2 abonelik/checkout adımını tamamla.
4. **Create bucket** seçeneğine bas.
5. Bucket adını tam olarak `riffline-song-relay` yaz.
6. Storage class olarak **Standard** seç.
7. Konum seçimini **Automatic** bırak.

Bucket public yapılmamalıdır. `r2.dev` public URL özelliğini açma.

Bucket'ı panel yerine komutla da oluşturabilirsin:

```powershell
cd cloudflare\song-relay
npm install
npx wrangler login
npx wrangler r2 bucket create riffline-song-relay
```

## 2. Worker'ı kur

Bilgisayarda Node.js 20 veya daha yenisi bulunmalıdır. PowerShell'de proje
klasöründen:

```powershell
cd cloudflare\song-relay
npm install
npx wrangler login
npx wrangler deploy
```

İlk komut yalnızca Worker geliştirme aracını kurar. `wrangler login` tarayıcıda
Cloudflare hesabına izin vermeni ister. Deploy sonunda aşağıdakine benzer bir
adres gösterilir:

```text
https://riffline-song-relay.<hesap-adı>.workers.dev
```

Bu adresi kopyala.

Worker başka isimdeki bir bucket'a bağlanacaksa
`cloudflare/song-relay/wrangler.jsonc` içindeki `bucket_name` değerini değiştir.
Firebase veritabanı adresi farklıysa aynı dosyadaki
`FIREBASE_DATABASE_URL` değerini güncelle.

## 3. Çalıştığını kontrol et

Tarayıcıda veya PowerShell'de:

```powershell
curl.exe https://riffline-song-relay.<hesap-adı>.workers.dev/health
```

Beklenen cevap:

```json
{"ok":true,"service":"riffline-song-relay"}
```

## 4. Oyun yapılandırmasına adresi ekle

Kök dizindeki `multiplayer_config.json` dosyasında şu alanı doldur:

```json
{
  "firebase_database_url": "https://riffline-default-rtdb.europe-west1.firebasedatabase.app",
  "firebase_api_key": "...",
  "song_cloud_url": "https://riffline-song-relay.<hesap-adı>.workers.dev",
  "ice_servers": []
}
```

Sonunda `/` bulunmaması tercih edilir; oyun bulunsa da otomatik temizler.
Worker adresini ekledikten sonra APK/AAB yeniden export edilmelidir.

## 5. 24 saatlik otomatik silme kuralı

R2 bucket sayfasında **Settings > Object lifecycle rules** bölümünü aç:

1. **Add rule** seç.
2. İsim: `delete-multiplayer-songs-after-1-day`
3. Prefix: `rooms/`
4. Eylem: objectleri sil/expire et.
5. Süre: 1 gün.
6. Kuralı kaydet.

Worker manifestte de 24 saatlik son kullanım zamanı yazar; asıl fiziksel silme
R2 lifecycle kuralıyla yapılır. Bu kural ücretsiz depolama kotasının
beklenmedik şekilde dolmasını önler.

Aynı kuralı komutla eklemek istersen:

```powershell
cd cloudflare\song-relay
npx wrangler r2 bucket lifecycle add riffline-song-relay --expire-days 1
```

## 6. Test

1. Yeni Worker adresini içeren test APK'sını iki telefona kur.
2. İlk telefondan oda oluştur ve yerel bir şarkı seç.
3. Host ekranında `Şarkı buluta yükleniyor` ilerlemesini gör.
4. İkinci telefonla odaya gir.
5. İkinci telefonda `Şarkı Cloudflare'dan indiriliyor` ilerlemesini gör.
6. İndirme bittiğinde oyuncunun `song_ok` durumu otomatik true olur.
7. R2 bucket içindeki `rooms/<ODA>/<FINGERPRINT>/` yolunda manifest ve parçaları
   kontrol et.

Üç veya dört oyunculu testte host bir kez upload yapar; tüm misafirler kendi
bağlantılarıyla R2'den indirir.

## Güvenlik notları

- R2 erişim anahtarı APK içine konulmaz.
- Bucket private kalır.
- Worker her istekte Firebase tokenını ve oda üyeliğini denetler.
- Upload işlemini yalnızca Firebase odasındaki host yapabilir.
- Dosya yolları, parça boyutları, toplam 512 MB sınırı ve MD5 değerleri
  doğrulanır.
- Oda kodunu bilmek tek başına dosya indirmeye yetmez.
- Üretimde Cloudflare dashboard üzerinden Worker kullanım bildirimleri ve R2
  bütçe/harcama uyarıları açılmalıdır.

## Sorun giderme

- `Firebase token rejected`: Firebase Anonymous Authentication açık olmalı.
- `Room not found`: Oda kapanmış veya kod yanlış olabilir.
- `Only the room host may upload`: Upload isteğini yapan oyuncu oda sahibi değil.
- `Song is still uploading`: Host uploadı henüz tamamlamıştır; istemci otomatik
  tekrar dener.
- Cloudflare erişilemezse istemci yaklaşık 90 saniye sonra mevcut WebRTC
  aktarımını dener.
