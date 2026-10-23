# Supabase hesap ve ekip kurulumu

Bu sürümde gerçek hesap bölümü, e-posta/şifre kayıt ve giriş, doğrulama bekleme/yeniden gönderme, çıkış, parola sıfırlama dönüşü ve yeni parola kaydı ile ekip oluşturma/listeleme/ad değiştirme kodu vardır. Sunucuya erişmek için aşağıdaki kurulumu tamamlayın. Demo kayıtları ayrı `vardiya.data.v1` deposunda kalır; otomatik aktarılmaz.

## Yapı

- `lib/account/account_service.dart`: Tek Supabase istemcisi, yapılandırma, Auth/DB adaptörü ve test edilebilir hesap kontrolcüsü. UI doğrudan Supabase sorgusu çalıştırmaz.
- `lib/account/account_page.dart`: Türkçe hesap ve ekip ekranları. Üstteki **Demo · Yerel / Gerçek hesabım** geçişi iki alanı ayırır.
- `supabase/migrations/202610230001_accounts_and_teams.sql`: Profiller, ekipler ve üyelikler; grant/RLS, kullanıcı profili trigger'ı ve RPC'ler.
- `supabase/tests/tenant_access.sql`: İki farklı kullanıcıyla veritabanı düzeyinde 15 pgTAP erişim/tutarlılık kontrolü. Gerçek e-posta göndermez; transaction sonunda rollback yapar. Yalnız test veritabanında çalıştırın.

## 1. Supabase projesi

Mevcut geliştirme projenizi kullanın veya Supabase Dashboard'da bir geliştirme projesi oluşturun. Bu görevde proje oluşturulmadı, ücretli hizmet açılmadı veya dağıtım yapılmadı. Auth > Providers altında Email sağlayıcısını ve **Confirm email** seçeneğini açık tutun. Parola politikasını en az 8 karakter olarak yapılandırın; UI da bunu doğrular.

Project Connect/API Keys bölümünden yalnız **publishable** (`sb_publishable_…`) anahtarı ve Project URL'yi alın. `sb_secret_…`, `service_role`, legacy JWT ve DB parolası uygulama yapılandırmasına kabul edilmez. Sunucu yönetim parolaları yalnız CLI/Dashboard içindir; Dart define, kaynak, test fixture veya web build içine konmaz. Publishable anahtar istemcide görünür; erişimin asıl sınırı RLS ve RPC grant'leridir.

Resmi sürüm ve kullanım: [supabase_flutter 2.18.3](https://pub.dev/packages/supabase_flutter/versions/2.18.3), [Flutter API](https://supabase.com/docs/reference/dart/introduction). Bağımlılık kararlı 2.18.3 sürümüne sabitlenmiştir; prerelease 3.x kullanılmaz.

## 2. Migration

Supabase CLI'yi resmi [CLI kurulum belgesine](https://supabase.com/docs/guides/local-development/cli/getting-started) göre kurun. Bağlı geliştirme projesi için PowerShell:

```powershell
cd C:\development\vardiya
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push --dry-run
supabase db push
```

Migration yalnız dosyadan uygulanmalı; Dashboard'da ayrı, izlenmeyen politika veya rol değişikliği yapmayın. CLI'nin istediği yönetim bilgilerini istemci config dosyasına yazmayın.

Yerel Docker + Supabase CLI varsa (bu bilgisayarda bulunamadı):

```powershell
supabase start
supabase migration up --local
supabase test db
supabase status
```

`supabase/config.toml` geliştirme portlarını ve e-posta doğrulamayı içerir. `supabase status` çıktısındaki yerel posta yakalayıcısı Mailpit/Inbucket adresini açarak **yalnız yerel test e-postalarını** inceleyin. Bu görevde gerçek kişilere test mesajı gönderilmedi. CLI sürümünüz yalnız eski JWT anon anahtarı sunuyorsa güncel CLI/yerel anahtar desteğini yapılandırın; istemcinin publishable doğrulamasını aşmayın.

### Erişim modeli

`profiles.id` Auth kullanıcısına bağlıdır. Profilde uygulama genelinde rol yoktur. `team_members(team_id,user_id,role)` ekip kapsamındaki `owner`, `manager`, `employee` değerlerini tutar. Kayıtlı kullanıcı metadata'sından rol okunmaz.

Ekip oluşturma `create_team(team_name)` ile tek transaction'dır: `auth.uid()` zorunludur; ekip ve sahip üyeliği birlikte yazılır. `rename_team(target_team,team_name)` yalnız o ekibin sahibi/yöneticisi için çalışır. `search_path` boş ve nesne adları şema ile nitelendirilmiştir. RPC'lerde çağıran kontrolü vardır; PUBLIC/anon execute kaldırılmıştır.

İstemci tablolarda yalnız SELECT alır. RLS yalnız kullanıcının üye olduğu ekipleri ve bunların üyeliklerini gösterir; profil yalnız kendisine görünür. Tahmin edilen başka ekip ID'siyle SELECT boş döner; doğrudan yazma, sahiplik/üyelik/rol değiştirme reddedilir. `private.is_team_member` definer fonksiyonu politika döngüsünü önler; yalnız üyelik boolean'ı hesaplar. `private` API'ye açık şemalara eklenmemelidir. Şimdilik istemciden davet/üye ekleme veya sahip devri endpoint'i yoktur.

## 3. SMTP ve e-posta doğrulama

Supabase'in varsayılan SMTP'si yalnız projenin organizasyon ekip üyelerine ait önceden yetkilendirilmiş adreslere gönderir. Resmi belgedeki güncel sınır **saatte 2 mesajdır**, değişebilir; teslimat garantisi/SLA yoktur. Üretim kullanıcılarına e-posta göndermek için kendi SMTP sağlayıcınızı Dashboard'da yapılandırın. Bu sınırı aşmak için **Confirm email'i kapatmayın**. SMTP parolasını Flutter'a koymayın. Bu görevde sağlayıcı hesabı/ücretli hizmet etkinleştirilmedi. Kaynak: [Supabase Custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp).

Varsayılan doğrulama ve parola kurtarma şablonlarındaki `{{ .ConfirmationURL }}` bağlantısını koruyun. PKCE dönüş kodu için sağlayıcının standart doğrulama endpoint'ini kullanın. Kaynak: [Parola akışları](https://supabase.com/docs/guides/auth/passwords), [kayıt API'si](https://supabase.com/docs/reference/dart/auth-signup).

## 4. Yönlendirmeler ve mobil bağlantılar

Dashboard > Authentication > URL Configuration:

- Site URL: `http://127.0.0.1:7357/` (yerel web geliştirme).
- Redirect URL izinleri: `http://127.0.0.1:7357/` ve `com.vardiya.app://auth/callback`.
- Dağıtım yapılacağı zaman kendi HTTPS web adresinizi hem izin listesine hem `AUTH_WEB_REDIRECT_URL` değerine ekleyin. Üretimde geniş wildcard kullanmayın. `localhost` ve `127.0.0.1`, farklı portlar ve son slash farkı önemlidir.

PKCE kullanılır. Bağlantıyı isteğin başlatıldığı tarayıcı profili/origin veya mobil uygulamada açın; başka cihaz/tarayıcıda verifier bulunmaz. Bu durumda yeni bağlantı istenmelidir. Merkezî adaptör ilk URL ve mobil `uriLinkStream` bağlantılarını işleyip SDK ile kodu değiştirir. `passwordRecovery` olayı yeni şifre ekranını açar; `updateUser(UserAttributes(password: ...))` tamamlanmadan işlem bitmiş sayılmaz. Kurtarma kullanıcısının kimliği ayrı bir işaretle korunur; sayfa yenilendiğinde aynı oturumda yeni şifre ekranına geri dönülür. Başarılı kayıtta/çıkışta işaret kaldırılır. Web callback kod/token parametreleri işlem sonrası adres çubuğundan kaldırılır. Şifre veya oturum değerleri loglanmaz; SDK debug logları kapalıdır.

Android manifestinde INTERNET izni, `com.vardiya.app` scheme / `auth` host / `/callback` path intent filter'ı ve Flutter'ın ikinci bir deep-link handler açmasını önleyen metadata eklendi. iOS Info.plist içinde URL scheme ve aynı handler ayarı vardır. Custom scheme bu ilk aşamada kullanılır; doğrulanmış universal/app links ve alan adı sahipliği sonraki dağıtım hazırlığıdır. Kaynak: [Mobil deep link belgesi](https://supabase.com/docs/guides/auth/native-mobile-deep-linking), [Redirect URL ayarları](https://supabase.com/docs/guides/auth/redirect-urls).

Mobil kurulum sonrası test için boş/süresi dolmuş callback'i Android'e yönlendirme örneği (gerçek tokenı terminal geçmişine yazmayın):

```powershell
adb shell am start -W -a android.intent.action.VIEW -d "com.vardiya.app://auth/callback?error=access_denied"
```

## 5. Flutter yapılandırması

PowerShell:

```powershell
cd C:\development\vardiya
Copy-Item config\supabase.example.json config\supabase.local.json
# Dosyadaki URL ve sb_publishable_ anahtarı kendi geliştirme projenizle değiştirin.
flutter pub get
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 7357 --dart-define-from-file=config/supabase.local.json
flutter build web --release --no-web-resources-cdn --dart-define-from-file=config/supabase.local.json
flutter run -d YOUR_ANDROID_DEVICE_ID --dart-define-from-file=config/supabase.local.json
```

Mevcut 7357 önizleme sunucusu çalışıyorsa ikinci bir sunucuyu aynı porta başlatmayın. Yerel sunucuyu durdurun veya diğer porta karşılık tüm redirect ayarlarını güncelleyin. `config/supabase.local.json` Git ignore içindedir; örnek dosyada gerçek bilgi yoktur. Alternatif define kullanımı:

```powershell
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 7357 `
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_YOUR_PUBLIC_KEY `
  --dart-define=AUTH_WEB_REDIRECT_URL=http://127.0.0.1:7357/ `
  --dart-define=AUTH_MOBILE_REDIRECT_URL=com.vardiya.app://auth/callback
```

Yapılandırma olmadan `flutter run -d chrome` Demo'yu çalıştırır. Hesap bölümünde kurulum açıklaması gösterilir. Geçersiz/privileged anahtar reddedilir. Oturum geri yüklenirken yükleniyor gösterilir. Ekip sonuçları sadece bellekte tutulur; çıkış/hesap değişiminde temizlenir ve önceki hesaptan bekleyen yanıtlar sürüm sayacıyla atılır. Demo verileri veya tüm shared preferences deposu topluca temizlenmez. Çıkış bu cihazın oturumunu kapatır, başka cihazlardaki oturumları sonlandırmaz.

## 6. Kabul kontrolü

Kurulmuş yerel Supabase ile iki kullanıcıyı yerel posta kutusundan doğrulayın. A kullanıcısı ekip oluşturup adını değiştirsin. Çıkış yapıp B ile giriş yapın; A ekibi görünmemeli. `supabase test db` bilinen A ekip ID'siyle okuma/yazma ve RPC yetki ihlallerini gerçek Postgres rolleri/JWT claims altında sınar; yalnız arayüz filtresini test etmez. Sahip üyeliği aynı işlemde oluşmalı, geçersiz ad başarısız olduğunda yarım ekip kalmamalı. [Veritabanı test belgesi](https://supabase.com/docs/guides/database/testing).

Ayrıca doğrulama yeniden gönderme, geçersiz parola, açık oturumla uygulamayı yeniden açma, parola kurtarma bağlantısından yeni şifre kaydı, eski şifreyle girişin reddi, süresi dolan bağlantı, çevrimdışı durum ve mobil callback'i sınayın. Gerçek kişilere test e-postası göndermeyin; yerel Mailpit kullanın.

Bu görevde canlı Supabase bağlantısı, SMTP teslimatı, SQL migration/pgTAP çalıştırması ve Android/iOS callback doğrulaması yapılmadı: Supabase CLI/Docker/Postgres ve proje bilgileri yoktu. Flutter testlerindeki hesap adaptörü sahtedir; gerçek Supabase başarısı anlamına gelmez. Test sonuçları ana README'de ayrıca yer alır.

## Sonraki görev

Çalışan daveti/kabulü ve gerçek ekiplerin ortak vardiya planı aşağıdaki ayrı migration’larla eklendi. Demo planı ayrı kalır; yerel kayıtlar yüklenmez. İzin/değişim talepleri, bildirimler ve dışa aktarma sonraki aşamalardır.

## GitHub Actions: izole PostgreSQL erişim testleri

`.github/workflows/supabase-tests.yml`, standart `ubuntu-latest` runner üzerinde resmî `supabase/setup-cli@v3` ile CLI **2.121.0** kurar. Migration, SQL testleri, `supabase/config.toml` veya workflow değiştiğinde main push ve pull request olaylarında çalışır; Actions > Supabase tenant access tests > Run workflow ile elle de başlatılabilir. Yalnız `contents: read` izni kullanılır.

Her çalışma temiz checkout ve runner'ın Docker ortamında geçici bir Supabase PostgreSQL örneği oluşturur. `supabase db start` ardından `supabase db reset --local --no-seed` ile depodaki migration'lar boş yerel test veritabanına uygulanır. `supabase test db --local` gerçek PostgreSQL üzerinde eski erişim testleri ve yeni davet testlerini birlikte çalıştırır. Frankfurt projesine link/login/push yapılmaz; proje anahtarı, Supabase erişim tokenı veya gerçek DB parolası kullanılmaz. Test fixture'ı transaction sonunda rollback olur; geçici container/volume çalışma sonunda `supabase stop --no-backup` ile kaldırılır. Bu temizlik komutu yalnız CI runner'ın geçici verisi içindir.

SQL hatası veya başarısız pgTAP assertion CLI çıkış koduyla işi başarısız kılar. Bash `pipefail` tee'nin hatayı gizlemesini engeller. Ayrıca sonuçta `Files=4, Tests=168` ve `Result: PASS` bulunması zorunludur; eksik/atlanmış testler başarılı sayılmaz. Sonuç, Actions adım loglarında ve başarılı çalışmanın özetinde görülür. Önceden uygulanmış migration dosyaları değiştirilmez; erişim düzeltmesi gerekirse yeni migration eklenir.

Aynı testi Docker + Supabase CLI 2.121.0 ile yalnız boş/atılabilir yerel test ortamında çalıştırmak için:

```powershell
supabase db start
supabase db reset --local --no-seed
supabase test db --local
```

`db reset --local` o yerel Supabase veritabanını sıfırlar; mevcut geliştirme verilerinizi içeren bir yerel veritabanında kullanmayın. Uygulamanın yerel Demo deposu bu işlemlerden ayrıdır.

İlk CI çalışması PostgreSQL üzerinde 8 assertion geçtikten sonra test dosyasındaki iki eksik psql değişken tırnağı nedeniyle durdu. Yalnız test sözdizimi düzeltildi; daha önce uygulanmış migration ve erişim kuralları değiştirilmedi. Tam 15 test tamamlanmadan workflow başarılı sayılmaz.


## Çalışan davetleri — 23 Ekim 2026

Yeni migration: `supabase/migrations/202610230002_employee_invitations.sql`. Önceki migration ve mevcut 15 assertion değiştirilmedi. Bu görevde Frankfurt/geliştirme projesine migration uygulanmadı. Geliştirme projesinde denemeden önce yeni migration'ı inceleyip önceki bölümdeki `supabase db push --dry-run` ve `supabase db push` adımlarını kendiniz uygulayın; bu işlem eski migration'ı yeniden yazmaz. Flutter'ı kendi yerel publishable yapılandırmanızla derleyin.

### Kullanım

- Gerçek hesabınızla giriş yapın, Ekiplerim listesinden ekibin ayrıntısını açın. Kendi rolünüz listede görünür. Tüm üyeler ekip e-postalarını ve rollerini görüntüleyebilir.
- Sahip/yönetici, çalışanın e-postasını girip Davet oluştur seçer. **E-posta gönderilmez.** Oluşan kodu o anda kopyalayıp uygulama dışında kendiniz paylaşın. Ham kod ayrıntı kapatılınca, hesap değişince veya uygulama yenilenince geri getirilemez. Kaybolan kod için eski daveti iptal edip yeni davet oluşturun.
- Sahip/yönetici yalnız hâlâ geçerli, tüketilmemiş davetleri listeler ve iptal edebilir. Listede kod veya hash dönmez. Kod kopyalandığında cihaz panosunda kalabilir; uygulama dışında paylaşımı kullanıcı yönetir.
- Çalışan **hedef e-posta adresiyle doğrulanmış gerçek hesabına** girer. Ekibe katıl alanına kodu yazar, Daveti kontrol et ile ekip adını ve süreyi görür, ardından Daveti kabul et seçer. Önizleme tek başına üyelik oluşturmaz. Kabul sonrası ekip listesi yenilenir ve rol Çalışan olarak görünür.
- Bu aşamada yönetici/sahip verme, üye çıkarma, rol değiştirme ve ortak vardiya verisi yoktur. Demo ayrı kalır; veriler otomatik yüklenmez.

### Sunucu güvenliği

`team_invitations` RLS açık, istemciye doğrudan SELECT/INSERT/UPDATE/DELETE kapalıdır. Kod `pgcrypto.gen_random_bytes(32)` ile 256 bit rastgele üretilir ve yalnız oluşturma RPC'sinin cevabında bir kez döner. Tabloda sadece SHA-256 hash saklanır. Süre sunucuda 7 gündür.

`create_team_invitation` ve `cancel_team_invitation` o ekibin owner/manager üyeliğini doğrular. Liste RPC'si yalnız yöneticilere hedef e-posta, davet kimliği ve son kabul zamanını verir. Ham kodu yeniden sorgulayan endpoint yoktur. `preview_team_invitation` ve `accept_team_invitation`, `auth.uid()` ile gerçek `auth.users.email` ve `email_confirmed_at` alanlarını kontrol eder; JWT/istemciden e-posta, kullanıcı veya rol parametresi kabul etmez. E-posta eşleştirmesi trim ve küçük harf normalleştirmesiyle yapılır. Yanlış hedef, doğrulanmamış hesap, süre aşımı, iptal ve kullanım durumları detay sızdırmayan ortak yetki hatasıyla reddedilir.

Kabul RPC'si davet satırını `FOR UPDATE` kilitler, yeniden geçerlilik kontrolü yapar, sabit `employee` rolüyle üyelik ekler ve aynı transaction'da tüketimi işaretler. Üyelik zaten varsa `ON CONFLICT DO NOTHING` ile korunur, geçerli davet yine tüketilir; mevcut yüksek rol değiştirilmez veya yeniden verilmez. Aynı kodun sonraki kabulü reddedilir. İptal de aynı satır kilidini kullanır. Özel helper fonksiyonları public/anon/authenticated çağrısına kapalıdır; dış RPC'ler yalnız authenticated rolüne açıktır. Üye listesi yalnız ekip üyelerine açılır. [Satır kilitleri](https://www.postgresql.org/docs/current/explicit-locking.html), [pgcrypto](https://www.postgresql.org/docs/current/pgcrypto.html).

Hesap servisi, ekip/üyelik/bekleyen davet/önizleme ve yeni ham kodu sadece bellekte tutar. Çıkış ve hesap değişimi bunları temizler; eski hesaptan bekleyen yanıtlar atılır. UI kodu değiştirince eski önizleme geçersizleşir. Ham davet kodları, Auth oturumları ve gerçek kişisel bilgiler loglanmaz. Yeni RPC'ler hiçbir mesaj veya SMTP çağrısı yapmaz; hesap e-posta doğrulaması eskisi gibi korunur.

### Doğrulama

- `tenant_access.sql`: önceki **15** assertion aynen korundu.
- `invitations.sql`: **33** assertion; owner/manager/employee yetkileri, ekip dışı erişim, hash, kod uzunluğu/farklılığı, 7 gün, hedef Auth e-postası, sahte JWT e-posta bilgisi, doğrulanmamış hesap, önizleme, iptal, süre aşımı, ikinci kullanım, mevcut üyelik ve rol yükseltme engeli.
- Workflow **48/48 pgTAP assertion** ve iki test dosyası bekler; eksik/başarısız testte iş başarısız olur.
- `tool/test_invite_concurrency.py`: runner'ın sabit `supabase_db_vardiya` container'ında iki ayrı psql oturumu aynı kodu eşzamanlı kabul eder. Tam bir başarı, bir SQL reddi, tek üyelik ve tek tüketim kontrol edilir. Kod ve SQL hata içerikleri basılmaz. Script uzak bağlantı adresi veya gerçek kimlik bilgisi almaz. Yalnız geçici CI veritabanında kullanılmalıdır.
- İlk yeni migration çalışması [GitHub Actions'ta](https://github.com/veles1010/vardiya/actions/runs/39937318269) 48/48 assertion ve eşzamanlı kabul kontrolünden geçti. Bu gerçek PostgreSQL doğrulamasıdır; Frankfurt projesinde yeni migration'ın çalıştığı veya gerçek tarayıcı hesabıyla davetin kabul edildiği anlamına gelmez.
- Flutter davet testleri fake adaptörle hesap izolasyonu, bekleyen yanıtların atılması, kodun önizleme sonrası değişmesi, kopyalama, iptal ve kabul akışını sınar. 320 px ekran ve açık klavye koşulu da test edilir.

Gerçek ortamda kalanlar: yeni migration'ın sizin tarafınızdan geliştirme projesine uygulanması, iki doğrulanmış geliştirme hesabıyla tarayıcıda uçtan uca davet/kabul/iptal kontrolü ve Android/iOS cihaz kontrolü. Bu görevde bu adımlar, gerçek kişilere mesaj ve ortak vardiya bağlantısı yapılmadı.


## Gerçek ekiplerin ortak vardiya planı — 23 Ekim 2026

Yeni migration: `supabase/migrations/202610230003_shared_team_plans.sql`. Önceki iki migration, mevcut 48 SQL assertion ve davet eşzamanlılık testi aynen korundu. **Bu görevde Frankfurt projesine migration uygulanmadı.** Gerçek hesap, davet kabulü ve yönetici üye listesi kullanıcı tarafından iki hesapla doğrulandı; yeni ortak plan için aşağıdaki kabul senaryosu henüz gerçek geliştirme ortamında çalıştırılmadı. Önceki davet iptalinin tarayıcı kabul kontrolü de bekliyor.

### Kurulum ve kullanım

Yeni migration’ı inceleyin. Geliştirme projesine kendi yetkinizle uygulamadan önce mevcut bağlantınızı ve bekleyen migration listesini kontrol edin (`supabase migration list`, `supabase db push --dry-run`); yalnız beklediğiniz migration’ın uygulanacağını doğruladıktan sonra `supabase db push` çalıştırın. Bu komutlar gerçek geliştirme veritabanında değişiklik yapar; bu görev sırasında çalıştırılmadılar. İstemciye yeni secret veya DB parolası gerekmez. Mevcut publishable yapılandırmayla Flutter’ı yeniden derleyin/başlatın. Yeni migration olmadan Demo çalışır; gerçek plan isteği anlaşılır kurulum/bağlantı hatası verir.

Gerçek hesabım → Ekiplerim → ekip ayrıntısı → **Haftalık planı aç**. Owner/manager, tüm gerçek üyeler (kendisi dahil) için taslak atama oluşturur, düzenler, siler. Örnek çalışan/vardiya üretilmez. Başlangıç/bitiş ayrı tarih-saat olarak `YYYY-AA-GG SS:dd` biçiminde girilir; gece vardiyasında bitiş tarihini açıkça ertesi gün girin. İsim 1–100, not en fazla 2000 karakterdir. Form hesaplanan bitiş ve planlanan net süreyi gösterir. Masaüstünde üyeler satır, günler sütundur; hücreye basınca ayrıntı/düzenleme/silme açılır. Telefonda haftalık program ve gün seçimiyle günlük liste vardır.

**Yayımla · Tüm ekip taslağı** yalnız görünen haftayı değil, ekibin tüm tarihlerdeki taslağını yayımlar. Onay açıklaması kapsamı belirtir. Yönetici Taslak/Yayımlanmış arasında geçebilir. Employee yalnız kendi yayımlanmış programını görür; kullanıcı/rol seçimi veya yönetim kontrolleri sunulmaz. Her ekran girişinde ve Yenile ile sunucudan veri alınır. Otomatik canlı abonelik veya çevrimdışı gerçek plan önbelleği yoktur. Demo’nun kalıcı yerel deposu ve davranışı korunur, sunucuya yüklenmez.

### Model, zaman ve işlem güvenliği

- `team_plans`: ekip sürümü, son yayımlanan sürüm/zamanı, sabit `Europe/Istanbul` saat dilimi. İlk boş plan sürümü 0’dır.
- `team_shift_drafts`: UUID ile ilişkilendirilen ekip/üye atamaları. Ekip üyeliği bileşik foreign key ve RPC kontrolüyle doğrulanır. `btree_gist` exclusion constraint, aynı ekip/üye için `[başlangıç,bitiş)` kesişimini eşzamanlı işlemlerde de reddeder. Sınıra bitişik vardiyalar kabul edilir.
- `team_shift_published`: ad, not, başlangıç, bitiş, mola ve üye kimliğinin bağımsız kopyası. Taslağa veya şablona canlı bağlanmaz. Taslağı değiştirmek/silmek eski yayını değiştirmez.
- Üç tabloda RLS açık; public/anon/authenticated için doğrudan tablo okuma/yazma grant’i yoktur. Dış RPC’ler yalnız authenticated rolüne açık; private helper’lar istemciden çağrılamaz. `security definer` fonksiyonları boş search_path ve şema nitelikli nesneler kullanır, her işlemde gerçek `auth.uid()` üyeliğini/rolünü doğrular. Taslak okuma/yazma/yayımlama yalnız ekip owner/manager’ına açıktır. Yayımlanmış okuma employee için sunucuda `user_id=auth.uid()` ile sınırlıdır; başka kullanıcıyı seçen parametre yoktur. Yönetici kendi ekibinin yayımlanmış kopyasını görebilir. [Fonksiyon güvenliği](https://supabase.com/docs/guides/database/functions), [çakışma kısıtları](https://www.postgresql.org/docs/15/rangetypes.html#RANGETYPES-CONSTRAINT).
- Bütün taslak yazımları ve yayımlama ekip durum satırını kilitler, zorunlu `expected_version` değerini karşılaştırır ve sürümü artırır. Eski veriden gelen işlem `40001` ile reddedilir. Yayımlama aynı transaction içinde eski kopyayı değiştirip sürüm/zamanı kaydeder. Okuma tek SQL snapshot’ında meta veriyi ve vardiyaları alır; yarım program görülmez. İstemci hatadan/zaman aşımından sonra yazmayı durdurur ve **Yenile** ister: zaman aşımında işlem sunucuda tamamlanmış olabilir.
- Vardiya tarih-saatleri `timestamp without time zone` içinde **Europe/Istanbul sivil alanları**dır. API ofsetsiz ISO tarih-saat kullanır; Dart bunları UTC alanlarına sivil değer olarak taşır, `toLocal()` uygulamaz. PostgreSQL oturum/tarayıcı saat dilimi saatleri kaydırmaz. `published_at` denetim zamanı gerçek `timestamptz` değeridir. Gerçek planın “bu hafta” başlangıcı güncel İstanbul (UTC+03) tarihinden alınır. Ekip saat dilimini değiştirme bu sürümde yoktur.
- Bitiş başlangıçtan sonra, değerler sonlu ve dakika hassasiyetinde olmalıdır. Eşit saatler yalnız açıkça sonraki tarihle 24 saat olabilir. Mola tamsayı, 0 ile brüt süre arasında olmalıdır. Aynı domain hesabı hafta/ay kesişimini alır, molayı brüt süreye orantılı dağıtır; sadece gösterilen toplam yuvarlanır. Örneğin 31 Ekim 22:00–1 Kasım 06:00, 60 dakika mola: ekim 105, kasım 315 dakika. Bordro/fazla mesai hesabı yapılmaz.
- Hesap/ekip değişiminde ve çıkışta plan/üye/davet belleği temizlenir; eski bekleyen yanıtlar sürüm işaretleriyle atılır. Şifre, oturum, davet kodu ve kişisel bilgiler loglanmaz.

### İki hesaplı kabul senaryosu (migration sonrası)

1. Owner A ile gerçek ekibi açın; önceden katılmış employee B ve A için farklı vardiyalar girin. B’ye pazar 22:00–pazartesi 06:00, 60 dakika mola atayın. Aynı kişinin 05:59’da başlayan vardiyasının reddini, 06:00’da başlayan vardiyasının kabulünü kontrol edin.
2. B’nin ayrı tarayıcı oturumunda planı açın: ilk yayımlama öncesi boş açıklama olmalı; taslaklar, A’nın vardiyaları ve yönetici kontrolleri görünmemeli.
3. A ile Tüm ekip taslağı’nı yayımlayın; B ile Yenile yapın. B yalnız kendi vardiyalarını, not/mola ve ilgili haftaya düşen net toplamı görmeli. Farklı tarayıcı saat diliminde saatler aynı kalmalı.
4. A taslak vardiyanın adını/saatini değiştirip sonra silsin. B Yenile yapsa da önceki yayımlanmış vardiya kalmalı. A yeniden yayımladığında silinmiş vardiya B’den kaldırılmalı. Başka haftalarda da değişikliğin yayımlandığını kontrol edin.
5. A ile iki yönetici sekmesi açın; ikisi de aynı sürümü alsın. Birinde düzenleyip diğerinde yayımlamayı deneyin: eski sürüm reddedilmeli ve Yenile istenmeli. Yeni veriyi aldıktan sonra işlem yapılabilmeli.
6. Ekip dışı üçüncü hesap ekip ID’sini bilse de RPC okuma/yazma yapamamalı. B hesabından doğrudan taslak okuma/yazma/yayımlama reddedilmeli. Çıkış/hesap değişiminde önceki plan görünmemeli. Demo kayıtları ve önceki davet akışı korunmalı.

### Otomatik doğrulama

- `tenant_access.sql` 15 + `invitations.sql` 33 + `shared_plans.sql` 49 = **97/97 pgTAP assertion**. Roller/ekip izolasyonu, employee filtresi, taslak gizliliği, bağımsız yayın, düzenleme/silme sonrası koruma, yeniden yayımlama, eski sürüm, gece/çakışma/bitişik aralık, eşit/geçersiz tarih-saat, mola, dönem payı ve saat dilimi kontrol edilir.
- Aynı izole CI çalışmasında eski davet eşzamanlılık testi ve `tool/test_plan_concurrency.py` geçti. İki gerçek PostgreSQL oturumu çakışan ekleme, düzenleme/yayımlama ve çift yayımlamada yarıştırılır; her yarışta bir commit ve bir sürüm reddi, ardından tutarlı kopya doğrulanır.
- [Başarılı izole PostgreSQL Actions çalışması](https://github.com/veles1010/vardiya/actions/runs/39943841103). CLI 2.121.0, Ubuntu ve geçici yerel veritabanı kullanıldı; Frankfurt bağlantısı/anahtarı gerekmedi. Workflow üç dosyada tam 97 assertion ve `Result: PASS` arar; iki eşzamanlılık script’inin hataları işi başarısız yapar.
- Yerelde yalnız atılabilir Docker/Supabase veritabanında önceki `db start`, `db reset --local --no-seed`, `supabase test db --local` adımlarından sonra `python tool/test_invite_concurrency.py` ve `python tool/test_plan_concurrency.py` çalıştırılabilir. Script’ler yalnız sabit yerel container’a bağlanır. Bu Windows terminalinde CLI/Docker bulunmadığından SQL yerelde çalıştırılmadı; SQL doğrulaması yukarıdaki CI’dadır.
- Flutter testleri fake adaptörle çalışır; gerçek Supabase uçtan uca kontrolünün yerine geçmez. Gerçek ortak planın iki hesaplı tarayıcı ve Android/iOS cihaz kabul kontrolleri migration sonrası yapılmalıdır. Windows’ta iOS derlemesi yapılmadı.

Yerel son kontroller: **57/57 Flutter testi**, Dart format denetimi, `flutter analyze` ve `flutter build web --release --no-web-resources-cdn` başarılı. Gerçek uygulama gezinme testi, dar ekran/klavye, yayımlanmış çalışan programı, çakışma sonrası düzeltme, hesap geçişinde önbellek temizliği ve başarısız isteğin yenilenmesini kapsar.


## Tam gün izin talepleri ve yönetici onayı

Önceki ortak planın **beş manuel kabul testi kullanıcı tarafından başarıyla tamamlandı**. Gerçek hesap/ekip/davet/ortak plan ve açık/koyu tema davranışı korunur. Bu yeni izin akışının gerçek geliştirme ortamındaki kabul testi ise henüz yapılmadı.

Yeni migration: `supabase/migrations/202610230004_team_leave_requests.sql`. Önceki migration dosyaları değiştirilmedi. **Bu görevde Frankfurt’a migration uygulanmadı.** Yeni dosyayı inceleyip kendi geliştirme bağlantınızda önce `supabase migration list` ve `supabase db push --dry-run` ile yalnız beklediğiniz migration’ın beklediğini kontrol edin; ardından kendi yetkinizle `supabase db push` uygulayın. Mevcut publishable yapılandırmayla Flutter’ı yeniden derleyin/başlatın. Yeni migration olmadan eski gerçek ortak plan, eksik `leaves` alanını boş liste kabul ederek çalışır; yeni izin ekranı kurulmamış RPC için bağlantı/kurulum hatası gösterir. Yerel Demo kayıtları yüklenmez veya değiştirilmez.

### Kullanım

Gerçek hesabım → ekip ayrıntısı → **İzin talepleri**. Employee yalnız kendi taleplerini listeler ve **İzin talep et** ile başlangıç/bitiş gününü takvimden seçer (elle tarih girişi yoktur). Her iki gün dahildir, aynı gün de seçilebilir. Açıklama isteğe bağlıdır ve en fazla 500 karakterdir. İlk durum **Bekliyor**; çalışan sadece bekleyen talebini geri çekebilir. Bekleyen başvuru çizelgede onaylı izin olarak gösterilmez. Onaylandı, Reddedildi ve İptal edildi kayıtları silinmeden listede kalır.

Owner/manager kendi ekibinin taleplerini görür. Bekleyen talebi onaylar veya gerekçeyle reddeder; onaylı izni gerekçeyle iptal eder. Ret/iptal gerekçesi boş olamaz ve en fazla 500 karakterdir. İşlem geçmişinde aktör kimliği (mevcut üye listesinde varsa e-postası), sunucu karar zamanı ve gerekçe gösterilir. Yönetici kendi eski talebine karar veremez. Ekrana giriş ve **Yenile** güncel veriyi sunucudan alır; hata/eski sürümden sonra Yenile gerekir.

Onaylı izinler haftalık çizelgede **İzinli** olarak yer alır; mobil programda kapsadığı günlere göre süzülür. Çalışma toplamı yalnız vardiyalardan hesaplanır. Onaylı izin durumu vardiya taslağından/yayımlanmış kopyadan ayrıdır: izin onayı veya iptali, sonraki sunucu yenilemesinde doğrudan görünür; izin onayı için ek bir vardiya yayını gerekmez. Çalışanın programına yalnız kendi onaylı günleri gider; açıklama veya işlem geçmişi plan payload’ına eklenmez.

### Tutarlılık ve erişim

- `team_leave_requests` ve `team_leave_events` tablolarında RLS açık, istemciye doğrudan okuma/yazma grant’i kapalıdır. Okuma, oluşturma ve durum geçişleri yalnız authenticated RPC’lerden geçer. Üyelik/rol gerçek `auth.uid()` ile denetlenir; oluşturma RPC’si kullanıcı/rol/durum parametresi almaz ve yalnız ilgili ekibin employee üyesi adına `pending` oluşturur. Employee’nin talep/açıklama/geçmiş sorgusu sunucuda kendi kimliğiyle sınırlıdır. Takım dışı erişim, başka kişinin talebini çekme ve istemciden onay/rol yazımı reddedilir.
- Başlangıç/bitiş `date`, tam gün aralığı Europe/Istanbul sivil sınırlarıdır: `[başlangıç 00:00, bitiş+1 gün 00:00)`. `daterange(...,'[]')` exclusion constraint aynı ekip/kişinin bekleyen veya onaylı taleplerinin kesişmesini engeller. Ret/iptal yeni başvuruyu engellemez. Önceki geceden taşan vardiya kontrol edilir; bitiş gününü izleyen 00:00’da başlayan vardiya çakışmaz. [PostgreSQL aralık kısıtları](https://www.postgresql.org/docs/15/rangetypes.html#RANGETYPES-CONSTRAINT).
- Talep oluşturma mevcut vardiya ile çakışabilir. Yönetici liste RPC’si hem taslak hem yayımlanmış çakışmaları kaynak, ad ve tam tarih-saat ile verir; bu bilgi employee’ye açılmaz. Onay RPC’si bunları tekrar kontrol eder. Taslaktan silmek tek başına yeterli değildir: yayımlanmış eski vardiya da giderilene kadar onay engellenir. Otomatik vardiya silme/değiştirme yapılmaz.
- İzin işlemleri, vardiya kaydı/silme/yayımlama ile **aynı `team_plans` satırını aynı sırayla kilitler**, zorunlu ekip sürümünü kontrol eder ve sürümü artırır. Böylece çalışan başvurusu da eski yönetici ekranını geçersiz kılabilir. Kararlar ayrıca talep `revision` ve geçiş durumunu doğrular; çift karar/tekrar onay reddedilir. Önce ekip, sonra talep kilitlenir. [Satır kilitleri](https://www.postgresql.org/docs/17/explicit-locking.html).
- Yeni taslak ve yayımlanmış vardiya satırlarında trigger, aynı kilit altında onaylı izin kesişimini reddeder. Mevcut vardiya RPC’lerinin sürüm denetimi ve atomik yayımlama davranışı korunur. Onay ile vardiya/yayım yarışında eski işlem reddedilir; tutarsız onaylı izin + vardiya durumu oluşmaz. İzin iptali vardiyaları geri oluşturmaz.
- Her geçiş sunucu aktör/zaman/gerekçesiyle ayrı bir event ekler; onaylı izin iptalinde ilk onay olayı korunur. İstemci silme endpoint’i yoktur. Hesap/ekip değişiminde ve çıkışta talepler temizlenir; eski bekleyen yanıtlar atılır. Başarılı izin yazımı plan önbelleğini de geçersiz kılar. Açıklamalar, gerekçeler, şifreler ve oturumlar loglanmaz.

### Kısa iki hesaplı kabul senaryosu (migration sonrası)

1. Doğrulanmış employee B kendi ekibini açsın. İzin talepleri → İzin talep et ile iki gün seçip kısa açıklamayla göndersin. Bekliyor görünmeli; haftalık programda henüz İzinli olmamalı. Aynı aralıkta ikinci talep reddedilmeli; aynı gün seçimi bir tam gün olmalı.
2. Owner/manager A aynı ekibin talebini görsün. Çakışmayan talebi onaylasın. B Yenile yaptığında Onaylandı ve programında İzinli görmeli; net çalışma süresi artmamalı. B başka çalışanın talebini/açıklamasını görememeli.
3. B mevcut vardiya günü için başka talep oluştursun; A çakışan **Taslak/Yayımlanmış** vardiya ad/saatlerini görsün. Önceki geceden taşan vardiya da listelenmeli. Sadece taslağı silmek onay için yeterli olmamalı. Planı düzenleyip yeniden yayımladıktan ve talepleri yeniledikten sonra A onaylayabilmeli.
4. A onaylı izin gününe vardiya kaydetmeyi denesin: reddedilmeli. İznin son gününü izleyen 00:00’da başlayan vardiya kabul edilmeli. İki yönetici sekmesinde eski sürümden onay/kayıt/yayım denemesi Yenile istemeli.
5. B bekleyen talebini geri çeksin; İptal edildi olarak kalmalı. A başka bekleyen talebi boş gerekçeyle reddedememeli; gerekçeyle reddettiğinde B nedeni görmeli. A onaylı izni gerekçeyle iptal etsin; B’nin takviminden kalkmalı, işlem geçmişinde hem ilk onay hem iptal aktörü/zamanı kalmalı. Ret/iptal sonrası aynı günler için yeni başvuru yapılabilmeli.

### Doğrulama ve kalanlar

[Başarılı GitHub Actions çalışması](https://github.com/veles1010/vardiya/actions/runs/39959977345): eski **97** + `supabase/tests/leave_requests.sql` içindeki **71** = **168/168 pgTAP assertion** gerçek, izole PostgreSQL’de geçti. Workflow dört dosyada tam bu sayıyı ve `Result: PASS` arar. CLI 2.121.0 ve standart Ubuntu runner kullanılır; Frankfurt bağlantısı veya gerçek proje sırları gerekmez. Mevcut davet/ortak plan eşzamanlılık script’leri değişmeden geçti. Yeni `tool/test_leave_concurrency.py`, ayrı gerçek PostgreSQL oturumlarıyla onay/kayıt, onay/yayımlama, iptal/kayıt, çift karar ve çakışan başvuruyu yarıştırır; geçerli tek sonuç, tutarlı vardiya/izin durumu ve tek karar olayı doğrulanır.

Yalnız atılabilir yerel Docker/Supabase ortamında mevcut `supabase db start`, `supabase db reset --local --no-seed`, `supabase test db --local` komutlarından sonra üç `tool/test_*concurrency.py` script’ini çalıştırın. `db reset --local` o yerel test DB’sini siler; gerçek geliştirme verisi bulunan DB’de kullanmayın. Bu Windows terminalinde CLI/Docker yoktu, SQL doğrulaması yukarıdaki CI’da yapıldı.

Flutter: **67/67 test** (57 mevcut + 10 izin testi), format denetimi, `flutter analyze` ve `flutter build web --release --no-web-resources-cdn` başarılı. Yeni testler fake adaptörle tarih seçici, iki ucu dahil günler, employee geri çekme, onay, gerekçeli ret/iptal, hesap/ekip izolasyonu, eski sürüm, çakışma kaynağı, 320 px/açık klavye, iki tema ve sıfır çalışma toplamlı takvim/çizelgeyi sınar. Fake Flutter testleri gerçek Supabase uçtan uca testi değildir.

Gerçek ortamda kalanlar: yeni migration’ın sizin tarafınızdan geliştirme projesine uygulanması, yukarıdaki iki hesaplı izin kabul senaryosu ve Android/iOS cihaz kontrolleri. Bu görevde Frankfurt’a migration, gerçek kişilere mesaj veya cihaz testi yapılmadı. Windows’ta iOS derlemesi yapılmadı. İzin hakkı/bakiye, bordro/yasal hak, vardiya takası, bildirim ve ödeme bu kapsamda yoktur.
