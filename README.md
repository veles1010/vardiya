# Vardiya

Türkçe, Material 3 tabanlı Flutter uygulaması. Yerel **Demo** prototipi korunur; ayrı **Gerçek hesabım** bölümünde Supabase hesapları ve gerçek ekip altyapısı eklenmiştir. Gerçek ekipler henüz vardiya planına bağlanmaz.

## Supabase hesapları

Kurulum ve migration komutları, SMTP/doğrulama, web/mobil callback adresleri, PowerShell yapılandırması ve erişim testleri: [Supabase kurulum rehberi](docs/SUPABASE.md). Yapılandırma olmadan Demo çalışır; veriler sunucuya aktarılmaz.

23 Ekim 2026: `supabase_flutter 2.18.3` ile kayıt/giriş/çıkış, doğrulama bekleme/yeniden gönderme, kurtarma dönüşü ve yeni şifre, gerçek ekip oluşturma/listeleme/ad değiştirme kodu eklendi. Canlı Supabase kurulumu olmadığından e-posta ve DB/RLS sonuçları henüz doğrulanmadı. SQL erişim testleri depoda hazırdır; Flutter hesap testleri fake adaptör kullanır.

## Hızlı başlangıç

Proje doğrudan `C:\development\vardiya` içindedir. Flutter 3.47.0 / Dart 3.13.0 ile geliştirilmiştir. Bağımlılıkların çözümlenmiş sürümleri `pubspec.lock` içindedir.

```powershell
cd C:\development\vardiya
flutter pub get
flutter run -d chrome --web-port 7357
```

Chrome yerine `-d edge` kullanılabilir. Web verileri tarayıcı profili ve origin (protokol + host + port) bazında saklanır. Aynı verileri görmek için aynı tarayıcı, adres ve portu kullanın. Çalışan önizleme sunucusu varsa doğrudan `http://127.0.0.1:7357` adresini açın; aynı porta ikinci sunucu başlatmayın. `localhost` ile `127.0.0.1` ayrı depolama alanlarıdır.

Android için Android SDK, uygun JDK ve emülatör veya USB hata ayıklaması açık cihaz gerekir:

```powershell
flutter doctor -v
flutter devices
flutter run -d <android-cihaz-kimliği>
flutter build apk --debug
```

APK: `build\app\outputs\flutter-apk\app-debug.apk`. Lisans uyarısı alırsanız `flutter doctor --android-licenses` çıktısını inceleyerek gerekli lisansları kendiniz kabul edin. Bu proje için mevcut Android araçlarıyla debug APK üretilebilmiştir; fiziksel Android cihaz/emülatör üzerinde çalıştırma ayrıca yapılmalıdır.

Web dağıtım dosyalarını üretmek için:

```powershell
flutter build web --release --no-web-resources-cdn
```

`build/web` klasörünü bir HTTP sunucusuyla sunun; `index.html` dosyasını `file://` ile açmayın. Yazı tipleri ve CanvasKit yerel derlemeye dahildir. Mağaza yayını veya internet üzerinde dağıtım yapılmamıştır.

## Demo akışı

1. **Kişisel:** Aylık takvimde gün seçin veya telefonda günlük program oklarını kullanın. “Kayıt ekle” ile vardiya, izin veya dinlenme günü ekleyin. Kayıt menüsü üzerinden düzenleyin/silin. Yaklaşan/devam eden vardiya ve seçilen ayın planlanan net çalışma süresi gösterilir.
2. **Ekip yönetimi:** Ekip oluşturun veya mevcut ekibin adını düzenleyin. “Çalışanlar” bölümünde ad/görev ekleyin, düzenleyin veya aktif anahtarını kapatarak pasifleştirin. Geçmiş atamalar kalır; pasif çalışana yeni atama yapılamaz. Aynı ekranda tekrar aktifleştirilebilir.
3. **Şablonlar:** Sabah, akşam ve gece şablonlarını düzenleyin veya yenisini ekleyin. Şablonlar tüm ekiplerce kullanılabilir. Bir şablonu değiştirmek mevcut vardiyaları değiştirmez; yeni girişte yalnız alanları doldurur.
4. **Haftalık plan:** Vardiya atayın. Masaüstünde çalışanlar satır, pazartesi–pazar günleri sütundur; yatay kaydırma desteklenir. Hücredeki vardiyaya tıklayıp düzenleyin veya açılan formdan silin. Telefonda gün seçimi ve o günün atamaları listelenir.
5. **Yayımlama:** “Tüm ekip taslağını yayımla” seçili ekibin **bütün tarihlerdeki** taslağını tek işlemle kopyalar; yalnız görüntülenen haftayı yayımlamaz. Ekleme, düzenleme ve silmeler birlikte yayımlanır. Onay penceresi kapsamı açıklar.
6. **Çalışan:** “Demo çalışan seçimi” ile örnek çalışanı seçin. Yalnız o kişinin son yayımlanmış haftalık programı ve aylık takvimi görünür. Burada yönetici düzenleme kontrolleri yoktur. Pasif çalışanların geçmiş yayımları da incelenebilir.
7. Taslağı değiştirin; çalışan ekranının değişmediğini görün. Yeniden yayımlayın; yeni kopya görünür. Sayfayı yenileyin veya uygulamayı yeniden açın; kayıtlar korunur.

Demo modları ve çalışan seçimi kimlik doğrulama değildir. Kişisel kayıtlar ekip atamalarından tamamen ayrı listelerde saklanır.

## Zaman ve hesap kuralları

- Her vardiya ayrı başlangıç ve bitiş **tarih-saat** değerleri taşır. 24 saat biçimi ve pazartesi başlayan hafta kullanılır.
- `22:00–06:00` için **Ertesi gün biter** seçilmelidir; gece şablonu bunu açık olarak doldurur. Aynı gündeki eşit saatler reddedilir. 24 saatlik vardiya ancak ertesi gün seçimi açıkça yapıldığında mümkündür.
- Çakışma yarı açık `[başlangıç, bitiş)` aralığıyla kontrol edilir. Bir vardiyanın bittiği anda diğeri başlayabilir. Önceki günden taşan vardiyalar da karşılaştırılır. Kişisel izin/dinlenme kayıtları bütün günü kaplar ve aynı kişinin diğer kayıtlarıyla çakışamaz.
- Mola dakika cinsinden tam sayıdır; negatif veya brüt vardiya süresinden büyük olamaz. Süreye eşit mola sıfır net süre verir. İzin ve dinlenme çalışma süresine eklenmez.
- **Mola dağıtımı:** Gerçek mola saati tutulmadığından ücretsiz mola vardiya boyunca eşit oranla dağıtılır. Bir döneme düşen net süre = dönemle kesişen brüt süre × `(toplam brüt − mola) / toplam brüt`. Örneğin 31 Ekim 22:00–1 Kasım 06:00, 60 dk mola: ekime 105 dk, kasıma 315 dk düşer. Haftalık sınırda aynı kural uygulanır. Hesapta kesirler korunur, yalnız gösterilen toplam en yakın dakikaya yuvarlanır.
- Gece vardiyası devam ettiği günlerde de görünür; “devam ediyor” açıklaması vardır. Kartta vardiyanın bütün süresi, hafta/ay toplamlarında yalnız dönemle kesişen süre gösterilir. Toplamlarda kayıt iki kez sayılmaz.
- Bütün saatler Türkiye sivil saati olarak yorumlanır. Tarih alanları Dart `DateTime.utc` içinde **sivil alanlar** olarak saklanır; gerçek UTC anı veya otomatik saat dilimi dönüşümü değildir. Cihazın saat dilimi değiştiğinde vardiya saatleri kaymaz. Bugün/şimdi cihaz tarihinden alınır; Türkiye dışı kullanım ve saat dilimi dönüşümleri bu aşamanın kapsamı dışındadır.
- Sonuçlar **planlanan net çalışma süresi**dir. Bordro, ücret veya yasal fazla mesai hesabı yapılmaz.

## Yapı ve kalıcılık

- `lib/domain.dart`: Değişmez veri nesneleri, kararlı kimlikler, çakışma ve süre hesapları, ilk örnek veri.
- `lib/data.dart`: `ScheduleRepository` arayüzü, `LocalScheduleRepository` ve `ScheduleStore`. UI bu arayüz üzerinden çalışır; sonraki aşamada sunucu deposu eklenebilir.
- `lib/main.dart`: Üç Demo görünümü ve duyarlı sayfa düzeni.
- `lib/editors.dart`, `lib/widgets.dart`: Türkçe formlar, hata mesajları, takvim ve ortak görsel bileşenler.
- `test/`: İş kuralları, saklama/yayımlama ve kullanıcı akışı testleri.

`shared_preferences` Async API ile sürümlenmiş tek JSON belge (`vardiya.data.v1`) saklanır. Webde LocalStorage; Android/iOS'ta platformun uygulama depolaması kullanılır. Paket: https://pub.dev/packages/shared_preferences

Örnekler yalnız anahtar yoksa bir kez oluşturulur. Bozuk veya bilinmeyen veri sürümünde veri sıfırlanmaz; açılış hatası gösterilir. Kayıt diske/platform deposuna yazılmadan görünür uygulama durumu güncellenmez. Yazma başarısızsa önceki durum korunur. Taslak ve yayımlanan listeler ayrı tutulur; yayımlama bütün belge içinde kaydedilir. Çalışan/ekip adları değişse de atamalar ID ile bağlı kalır.

## Kontroller

```powershell
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn
flutter build apk --debug
```

JavaScript'e özgü kimlik üretimi regresyonu için Node.js ile ek kontrol:

```powershell
dart compile js -O2 tool/web_smoke.dart -o build/web_smoke.js
node tool/run_web_smoke.cjs
```

**22 Ekim 2026 doğrulaması:** format ve analiz temiz; 30/30 Flutter testi geçti; JavaScript regresyon kontrolü geçti; web release ve Android debug APK üretildi. Gerçek uygulama içi tarayıcıda yeni vardiya ve not kaydedildi, sayfa yenilendi ve ikisinin de korunduğu görüldü. `docs/web-preview.png` bu kontrol sonrasındaki ekranı gösterir. Ayrı `flutter test --platform chrome` denemesi test yükleme aşamasında sonuçlanmadı ve durduruldu; başarılı kontrol olarak sayılmamıştır. Android cihaz/emülatör çalıştırması ve iOS derlemesi yapılmadı.

Testler; gece vardiyası, eşit saat, önceki günden çakışma, bitişte başlayan vardiya, geçersiz mola, hafta/ay sınırı, kesirli mola dağıtımı, çalışan filtreleme, taslak/yayımlama izolasyonu, pasifleştirme, bozuk veri, başarısız kayıt, tekrar açılış ve ana form akışlarını kapsar. 320 px ekran, açık klavye ve uzun çalışan adları için widget kontrolü vardır. Gerçek tarayıcıda yenileme kontrolü ayrıca yapılır.

## Bilinen sınırlamalar

- Gerçek hesap/ekip/davet akışı ve gerçek ortak plan Demo’dan ayrıdır. Yeni ortak plan migration’ı geliştirme projesine uygulanmadan gerçek plan kullanılamaz. Gerçek plan sunucudan girişte/Yenile ile alınır; çevrimdışı önbellek veya canlı abonelik yoktur.
- Shared preferences küçük Demo verisi için seçilmiştir; kritik üretim verisinin tek kaynağı olarak uygun değildir. Şifreleme, yedekleme, veri kurtarma ve çok kullanıcılı işlem garantisi yoktur. Tarayıcı verilerini temizlemek veya uygulamayı kaldırmak veriyi silebilir; gizli gezinme kalıcı değildir.
- Aynı origin'i birden çok sekmede eşzamanlı düzenlemek desteklenmez; son kayıt önceki değişiklikleri ezebilir. Demo tek etkin sekme/uygulama üzerinden denenmelidir.
- Gerçek ekip saat dilimi Europe/Istanbul olarak sabittir. Saat dilimi değiştirme ve ülkeye göre çalışma mevzuatı hesabı yoktur. Demo formu aynı/ertesi gün; gerçek ekip formu açık başlangıç ve bitiş tarihi kullanır.
- Demo kişisel takviminde izin/dinlenme kaydı bulunur; gerçek ekipte tam gün izin talebi ve yönetici kararı ayrı akıştadır. Vardiya değişimi talepleri henüz eklenmedi.
- Uygulama çevrimdışı depolama kullanır; web için yüklenebilir/offline PWA önbelleği henüz kurulmamıştır. Web sayfasını ilk açmak/yenilemek için yerel sunucu çalışıyor olmalıdır.
- iOS proje dosyaları oluşturuldu. **Windows üzerinde iOS derlemesi veya testi yapılmadı.** Mac + Xcode üzerinde `flutter pub get`, `flutter build ios --simulator` ve `flutter run -d <ios-simülatör-kimliği>` çalıştırılmalı; eklenti bağlantısı, klavye/güvenli alan ve uygulamayı kapatıp açınca kalıcılık doğrulanmalıdır. Fiziksel iOS cihazı için imzalama ayrıca yapılandırılmalıdır.
- Android debug APK üretmek, Android cihaz testi yapıldığı anlamına gelmez. Cihaz üzerinde klavye, süreç kapatma/yeniden açma ve depolama davranışı ayrıca kontrol edilmelidir.

## Sonraki aşamalar

1. Gerçek ortak plan için geliştirme migration’ı ve iki hesaplı cihaz/tarayıcı kabul kontrolü (kurulum ve senaryo aşağıda).
2. Üye/rol yaşam döngüsünün genişletilmesi.
3. Canlı güncelleme ve çevrimdışı senkronizasyon (mevcut ortak plan sunucuda sürüm denetimiyle paylaşılır).
4. Vardiya değişimi talepleri ve yönetici onayı (tam gün izin talebi/onayı eklendi).
5. Bildirimler ve hatırlatmalar.
6. Dışa aktarma.

Reklam, ödeme, otomatik vardiya üretimi ve mağaza yayını bu aşamaya dahil değildir.

### Form düzeltmeleri

Eski form hataları alan değişikliklerinde temizlenir; kaydetme güncel değerlerle depo doğrulamasını tekrar çalıştırır. Çakışma mesajı karşı kaydın adı ve tam tarih-saat aralığını içerir. Şablon seçenekleri saklanan saat aralığını ve ertesi gün bilgisini gösterir; şablon uygulama tüm alanları birlikte doldurur. Elle düzenleme devam eder. Formda hesaplanan bitiş ve planlanan net süre gösterilir.

Bu düzeltmede 35 Flutter testi geçti; 320 px ekran ve 280 px klavye alanında kişisel, ekip ve şablon formlarının kaydırma/Kaydet erişimi widget testleriyle doğrulandı. Taslak/yayımlama ve yeniden açılış testleri korunmuştur. Gerçek mobil cihaz, yeni Android/iOS derlemesi ve bu değişiklikler için ayrı tarayıcı otomasyonu çalıştırılmadı. Kayıtlı uygulama verileri veya şablonlar sıfırlanmadı.


### Hesap/ekip aşaması doğrulaması — 23 Ekim 2026

42 Flutter testi (mevcut 35 + 7 hesap testi), statik analiz ve web release derlemesi geçti. Hesap testleri fake adaptörle oturum geri yükleme, hesap değişimi sırasında eski sonuçların atılması, çıkışta bellek temizliği, geçersiz giriş/süresi dolmuş bağlantı, bağlantı hatası ve 320 px yeni şifre akışını sınar. Bunlar gerçek Supabase erişim testi değildir. `supabase/tests/tenant_access.sql` içindeki 15 pgTAP testi CLI/Docker/Postgres olmadığı için çalıştırılmadı; canlı Auth/SMTP ve Android/iOS deep link kontrolü yapılmadı. Sonraki kurulum adımı: geliştirme Supabase projesine migration uygulayın, Confirm email açıkken SMTP/redirect ayarlarını tamamlayın ve yalnız publishable anahtarla config dosyasını doldurun. Ortak vardiya ve çalışan daveti bu tur bağlanmadı.


### Çalışan daveti aşaması

Gerçek hesap bölümünde ekip ayrıntısı, üyeler/roller, e-posta hedefli 7 günlük davet oluşturma/kopyalama/iptal ve kodla önizleme/kabul eklendi. Bu akış davet e-postası göndermez. Yeni migration, güvenlik modeli, CI ve geliştirme projesinde kalan kurulum adımları [Supabase rehberinde](docs/SUPABASE.md#çalışan-davetleri--23-ekim-2026). Eski 15 SQL assertion ile 33 yeni assertion ve ayrı eşzamanlı kabul testi geçici GitHub PostgreSQL ortamında geçti. Frankfurt projesine migration uygulanmadı; ortak vardiya eklenmedi.

Bu aşamanın yerel kontrolleri: **47/47 Flutter testi**, format, analiz ve web release derlemesi başarılı. Flutter davet testleri fake adaptör kullanır; gerçek SQL/RLS kontrolleri ise yukarıda bağlantısı verilen geçici PostgreSQL Actions çalışmasında yapıldı.


### Gerçek ekip ortak planı

Gerçek hesabım → ekip ayrıntısı → **Haftalık planı aç**. Owner/manager gerçek üyelere (kendisi dahil) taslak vardiya atar, düzenler ve siler. **Yayımla · Tüm ekip taslağı** tüm tarihlerdeki programı tek transaction ile bağımsız yayımlanmış kopyaya geçirir. Employee yalnız kendi son yayımlanmış programını görür. Taslak değişiklikleri/silmeleri yeniden yayımlanana kadar çalışanı etkilemez. Masaüstünde ekip çizelgesi, telefonda gün seçimiyle günlük liste; haftalık planlanan net süre, tam tarih-saat, mola ve not vardır. Açılış ve Yenile sunucudan güncel veriyi alır. Eski sürümden yazım reddedilir ve Yenile istenir. Europe/Istanbul saatleri tarayıcının saat dilimine dönüştürülmez.

Yeni migration: `supabase/migrations/202610230003_shared_team_plans.sql`. **Frankfurt’a uygulanmadı.** Önce yeni migration’ı inceleyip geliştirme projenize kendiniz uygulayın; mevcut publishable yapılandırmayla uygulamayı yeniden başlatın. Demo verileri korunur ve yüklenmez. Kurulum, sunucu güvenliği ve iki hesaplı kısa kabul senaryosu [Supabase rehberinde](docs/SUPABASE.md#gerçek-ekiplerin-ortak-vardiya-planı--23-ekim-2026).

[GitHub Actions](https://github.com/veles1010/vardiya/actions/runs/39943841103) geçici gerçek PostgreSQL üzerinde **97/97 SQL assertion**, mevcut davet eşzamanlılığı ve üç ortak plan eşzamanlılık yarışını başarıyla tamamladı. Mevcut 48 assertion ve uygulanmış migration’lar korundu. Bu sonuç Frankfurt’ta yeni ortak planın doğrulandığı anlamına gelmez. Yerel Flutter sonuçları: **57/57 test** (47 mevcut + 10 ortak plan testi); 320 px/açık klavye, masaüstü çizelgesi, tam uygulama gezinmesi, hesap izolasyonu, hata/yenileme ve zaman hesapları kapsanır. Flutter testleri fake adaptör kullanır. Format ve statik analiz temiz; `flutter build web --release --no-web-resources-cdn` başarılı. Bu tur Android/iOS cihaz veya gerçek iki hesaplı ortak plan tarayıcı kabulü çalıştırılmadı; önceki davet iptalinin elle tarayıcı kontrolü de bekliyor.


### Görünüm ve tema

Ortak üst alandaki ay/güneş/otomatik tema ikonundan **Açık**, **Koyu** veya **Sistem** seçilir. Kayıtlı tercih yoksa varsayılan **Koyu** temadır. Sistem seçeneği işletim sisteminin görünümünü izler. Koyu tema saf siyah yerine antrasit zemin, ayrışan kart/form yüzeyleri ve okunabilir yeşil vurgular kullanır; takvim ve vardiya renkleri iki temaya da uyarlanır.

Tercih mevcut SharedPreferencesAsync altyapısıyla ayrı `vardiya.settings.theme.v1` anahtarında saklanır; Demo verisi ve Auth oturumundan bağımsızdır. Yenileme/yeniden açılış ve çıkış tercihi silmez. Tema değişimi gezinmeyi, seçili ekip/haftayı veya açık formdaki değerleri sıfırlamaz. Web başlangıç zemini Flutter yüklenmeden önce yalnız bu tercih anahtarına göre boyanır; uygulama çalışırken sayfa zemini de geçerli temayla eşleşir. Depolama izni yoksa koyu varsayılan açılır, kayıt başarısızlığı tema ikonunun yanında açıklamalı uyarıyla gösterilir.

Bu görünüm değişikliğinde yeni bağımlılık veya tekrar eden yeni test eklenmedi. Mevcut **57/57 Flutter testi**, format, analiz ve web release derlemesi başarılı. Gerçek tarayıcıda açık/koyu geçişi ve her iki tercihin yenileme sonrası korunması, açık formdaki notun tema değişiminde kalması, koyu ana ekran ve Demo haftalık çizelgesi görsel olarak kontrol edildi. 1280×900 masaüstü ve 320×800 dar ekran/form incelendi; deneme formları kaydedilmedi. Gerçek hesap bölümü giriş ekranındaydı: oturum gerektiren ekip/üye/davet/gerçek plan ekranlarının yeni temayla manuel kontrolü, çıkış sonrası tercih kontrolü, işletim sistemi temasını çalışma sırasında değiştirme ve Android/iOS cihaz kontrolü bu tur yapılmadı. Bu ekranlar merkezi temayı kullanır; iş mantığı ve sunucu erişim kuralları değiştirilmedi.

Yerel önizleme yeni `build/web` çıktısıyla `http://127.0.0.1:7357/` adresinde güncellendi; tarayıcıda **Ctrl+F5** ile yenileyin. Sonraki değişikliklerde mevcut yapılandırmayla yeniden web derlemesi üretip sayfayı yenileyin. `config/supabase.local.json` ve derleme çıktıları Git’e dahil edilmez.


### Gerçek ekiplerde tam gün izin

Önceki ortak planın **beş manuel kabul testi kullanıcı tarafından başarıyla tamamlandı**. Yeni izin akışı Gerçek hesabım → ekip ayrıntısı → **İzin talepleri** bölümündedir. Employee başlangıç/bitiş gününü takvimden seçer (iki uç dahil), isteğe bağlı en fazla 500 karakter açıklamayla talep oluşturur, yalnız kendi taleplerini görür ve bekleyeni geri çeker. Owner/manager onaylar, gerekçeyle reddeder veya onaylı izni gerekçeyle iptal eder; aktör/zaman/gerekçe geçmişi silinmez.

Bekleyen talepler onaylı izin olarak gösterilmez. Onaylı günler haftalık programda **İzinli** görünür ve çalışma toplamına eklenmez. Talep mevcut vardiyayla çakışabilir; onay hem taslak hem yayımlanmış vardiyaya karşı sunucuda engellenir. Planı düzeltip yeniden yayımlamak gerekir. Onaylı günlere vardiya kaydı/yayımı da sunucuda engellenir. Tüm izin ve plan işlemleri aynı ekip kilidi/sürümünü kullanır; eski veriden işlem Yenile ister. Demo ve tema tercihleri ayrı kalır.

Yeni migration: `supabase/migrations/202610230004_team_leave_requests.sql`. **Frankfurt’a uygulanmadı.** Kurulum ve kısa iki hesaplı kabul senaryosu [Supabase rehberinde](docs/SUPABASE.md#tam-gün-izin-talepleri-ve-yönetici-onayı). Geliştirme projesine kendi yetkinizle uygulayıp yeni istemciyi derledikten sonra gerçek izin kabul kontrolünü yapın.

[İzole PostgreSQL Actions](https://github.com/veles1010/vardiya/actions/runs/39959977345): **168/168 SQL assertion**, mevcut davet/plan yarışları ve beş yeni izin eşzamanlılık yarışı geçti. Flutter’da **67/67 test** (57 mevcut + 10 yeni), format, analiz ve web release derlemesi geçti; yeni Flutter testleri fake adaptör kullanır. Gerçek geliştirme hesabıyla yeni izin akışı ve Android/iOS cihaz kontrolü bu tur yapılmadı. İzin bakiyesi, bordro/yasal hak hesabı, takas, bildirim ve ödeme eklenmedi.
