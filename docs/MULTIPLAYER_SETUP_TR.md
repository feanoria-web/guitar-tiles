# Riffline Multiplayer Kurulumu

Riffline'ın çevrimiçi modu iki farklı oyun biçimini 2–4 oyuncuyla destekler:

- **Savaş / Battle:** Her oyuncunun skoru ayrıdır. Aynı enstrümanı birden fazla
  oyuncu seçebilir ve maç sonunda bireysel sıralama oluşur.
- **Band:** Oyuncular gitar, bas, davul veya klavye gibi farklı rolleri alır.
  Roller tekrarlanamaz; toplam skor ve ortak band canı birlikte hesaplanır.

Firebase yalnızca oda kodu, oyuncu listesi ve WebRTC bağlantı bilgilerini taşır.
Canlı skor paketleri Firebase'den geçmez; oyuncular arasında WebRTC ile gider.
Ev sahibi maçın otoritesidir ve diğer 1–3 oyuncu ona bağlanır.

## 1. Firebase projesini oluştur

1. [Firebase Console](https://console.firebase.google.com/) sayfasında yeni bir
   proje oluştur.
2. **Build → Authentication → Sign-in method** bölümünü aç.
3. **Anonymous / Anonim** sağlayıcısını etkinleştir.
4. **Build → Realtime Database** bölümünde bir veritabanı oluştur.
5. Oyuncularının çoğuna yakın bir veritabanı bölgesi seç.

Bu sistem Firebase Storage, Firestore veya ücretli bir sunucu kullanmaz.

## 2. Güvenlik kurallarını yükle

Realtime Database içindeki **Rules / Kurallar** sekmesine
[`firebase/database.rules.json`](../firebase/database.rules.json) dosyasının
içeriğini yapıştır ve **Publish / Yayınla** düğmesine bas.

Kurallar şunları sağlar:

- Odayı yalnızca anonim Firebase oturumu açmış kullanıcılar okuyabilir.
- Oda sahibi oda ayarlarını, teklifleri ve maç durumunu yazabilir.
- Katılan oyuncu yalnızca kendi oyuncu, cevap ve ICE alanını yazabilir.
- Oyuncu adı 18 karakterle sınırlıdır.

Firebase'in “test mode” kurallarını yayında bırakma. O kurallar süre dolunca
oyunu bozabilir ve süre dolmadan önce de veritabanını gereksiz yere açar.

## 3. Riffline yapılandırmasını doldur

Firebase Console'da **Project settings → General** bölümüne git. Gerekirse bir
Web App ekle; uygulamayı gerçekten web'de yayınlamak zorunda değilsin.
Gösterilen yapılandırmadan `apiKey` değerini al.

Realtime Database ana ekranında görünen adresi de kopyala. Örnek adresler:

- `https://proje-adi-default-rtdb.europe-west1.firebasedatabase.app`
- `https://proje-adi-default-rtdb.firebaseio.com`

Proje kökündeki
[`multiplayer_config.json`](../multiplayer_config.json) dosyasını düzenle:

```json
{
  "firebase_database_url": "https://PROJEN-default-rtdb.europe-west1.firebasedatabase.app",
  "firebase_api_key": "FIREBASE_WEB_API_KEY",
  "ice_servers": [
    {
      "urls": [
        "stun:stun.l.google.com:19302",
        "stun:stun1.l.google.com:19302"
      ]
    }
  ]
}
```

Firebase Web API anahtarı tek başına bir yönetici parolası değildir; gerçek
koruma Realtime Database kurallarıdır. Yine de anahtarı yalnızca bu Firebase
projesinde kullan ve API kısıtlamalarını Google Cloud Console'dan bu projeye
göre ayarla.

## 4. Yerel test

1. Oyunu iki ayrı bilgisayarda veya bilgisayar + Android cihazda aç.
2. İki cihazda da aynı şarkının aynı sürümünün yüklü olduğundan emin ol.
3. İlk cihazda ana menünün altındaki **Savaş / Battle** menüsünü aç.
4. Savaş veya Band'ı seçip **Oda Oluştur** düğmesine bas.
5. İkinci cihazda altı karakterli oda kodunu yazıp **Katıl** de.
6. Ev sahibi şarkıyı seçsin. Her cihaz şarkı parmak izini doğrular.
7. Oyuncular enstrüman ve zorluk seçip hazır olsun.
8. Ev sahibi **Maçı Başlat** dediğinde her cihaz önce şarkıyı hazırlar; tüm
   cihazlar hazır olduğunda ortak geri sayım başlar.

Tek bilgisayarda test etmek istersen editörden bir örnek ve dışa aktarılmış
Windows `.exe` dosyasından ikinci örneği çalıştırabilirsin. İki örneğin de aynı
Firebase yapılandırmasını ve aynı şarkıları görmesi gerekir.

## 5. Android / Play Store

Projede Android `INTERNET` izni açık tutulmalıdır. WebRTC'nin masaüstü ve Android
yerel kütüphaneleri `addons/webrtc_native/` altındadır ve export paketine dahil
edilir. AAB üretirken daha önce oluşturduğun release keystore ayarlarını
kullanmaya devam et.

Multiplayer değişikliklerinden sonra yeni bir AAB üretip imzasını doğrula.
Firebase için Android SHA-1 kaydı bu REST tabanlı anonim giriş akışında zorunlu
değildir.

## 6. STUN ve TURN konusu

Mevcut beta kurulumu ücretsiz STUN sunucularını kullanır. Ev ağı ve mobil ağların
çoğunda doğrudan bağlantı kurulur. Bazı kurumsal ağlar, okul ağları veya katı
operatör NAT'ları doğrudan WebRTC bağlantısını engelleyebilir.

Bu durumda daha sonra bir TURN hizmeti eklenebilir:

```json
{
  "urls": ["turn:turn.ornek.com:3478"],
  "username": "kisa-omurlu-kullanici",
  "credential": "kisa-omurlu-parola"
}
```

TURN trafiği sunucudan geçirir ve bant genişliği maliyeti doğurur. Kalıcı TURN
parolasını APK/AAB içine gömmek yerine kısa ömürlü kimlik bilgisi üreten küçük
bir servis kullanılmalıdır. İlk beta için TURN zorunlu değildir; bağlantı
başarı oranını gerçek oyuncularla ölçtükten sonra eklemek daha mantıklıdır.

## 7. Veri akışı ve sınırlar

- Oda: en fazla 4, en az 2 oyuncu.
- Topoloji: ev sahibi merkezli yıldız.
- Maç paketleri: güvenilir ve sıralı WebRTC DataChannel.
- Skor: istemciler yerel durum gönderir; ev sahibi sıra numarası ve skorun
  geriye gitmemesi gibi temel kontrolleri uygulayıp ortak görüntüyü yayınlar.
- Şarkı aktarımı yapılmaz. Telifli ses dosyaları Firebase'e veya diğer
  oyunculara yüklenmez.
- Ev sahibi bağlantıyı kapatırsa o maç sürdürülemez. Host migration sonraki bir
  sürümde eklenebilir.

## Sorun giderme

**“Multiplayer kurulumu gerekli”**

`multiplayer_config.json` içindeki iki Firebase değeri boş kalmıştır.

**“Firebase anonim oturum açılamadı”**

Authentication içindeki Anonymous sağlayıcısının etkin olduğunu ve API key'in
doğru olduğunu kontrol et.

**“Oda bulunamadı”**

İki cihazın aynı Firebase projesini kullandığını, oda kodunu ve Database
kurallarının yayınlandığını kontrol et.

**Oyuncu odada görünüyor ama WebRTC bağlanmıyor**

Farklı bir ağ veya mobil hotspot ile dene. Orada çalışıyorsa ilk ağ doğrudan
WebRTC trafiğini engelliyor olabilir; TURN gerekir.

**“Aynı şarkı bu cihazda bulunamadı”**

Şarkının adı yetmez. Chart/container ve yanındaki ses dosyalarının aynı sürümü
iki cihazda da bulunmalıdır.
