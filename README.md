# Soap Opera Studio — Flutter arayüz prototipi

Flutter mobil uygulaması. Giriş/kayıt ve dizi oluşturma/listeleme Supabase'e bağlı;
bölüm üretimi, oynatıcı, oylama ve maliyet ekranı henüz örnek (mock) veri kullanır.

## Çalıştırma

```bash
flutter create soap_opera_studio --platforms=android,ios
cd soap_opera_studio
# bu klasördeki lib/ ve pubspec.yaml dosyalarını üzerine kopyala
rm test/widget_test.dart      # Windows: del test\widget_test.dart
flutter pub get
flutter run
```

Gereken: Flutter 3.19 veya üstü (Dart >= 3.3).

## Supabase

1. Supabase projesinde `supabase/schema.sql` dosyasını SQL Editor'da çalıştır.
2. `lib/config.dart` içindeki URL ve publishable anahtarı kendi projenle eşleştir.
3. Authentication > Providers > Email: geliştirme için "Confirm email" kapatılabilir.

`service_role` / secret anahtarını asla uygulamaya veya repoya koyma.
`docs/dartpad_main.dart` tarayıcıda (DartPad) çalışan, Supabase'siz sahte veri sürümüdür.

## Ekranlar

| Ekran | Dosya | Demoda ne gösterir |
| --- | --- | --- |
| Giriş | `login_screen.dart` | E-posta/şifre, KVKK onayı (onaysız giriş kapalı), misafir izleme |
| Dizilerim | `home_screen.dart` | Dizi kartları, açık oylama bandı |
| Dizi detayı | `series_detail_screen.dart` | Karakterler (karakter kilidi), sezon planı, bölüm durumları |
| Oluştur | `create_series_screen.dart` | Tür, mekân, 2–4 karakter seçimi |
| Üretim durumu | `generation_status_screen.dart` | Mimarideki 8 adımlı hat (simülasyon) |
| Bölüm oynatıcı | `episode_player_screen.dart` | 9:16, Ken Burns, altyazı, AI etiketi |
| Oylama | `vote_sheet.dart` | Tek oy, canlı yüzdeler (örnek veri) |
| Maliyet | `cost_panel_screen.dart` | Bütçe kaydırıcısı + gerçek 0-1 knapsack: hangi sahne video olur |

## Sonraki adım (backend bağlantısı)

- `data.dart` mock verisi yerine Supabase tabloları (`series`, `episodes`, `polls`)
- Giriş: Supabase Auth
- Üretim durumu: Realtime ile `jobs` tablosu
- Maliyet: `cost_events` tablosu

## Oylama ve örnek veri
1. Supabase SQL Editor'da `supabase/003_seed_demo.sql` dosyasını çalıştır (önce uygulamadan hesap aç).
2. Diziler sekmesinde "Oy ver" bandı çıkar; oylar `votes` tablosuna yazılır, sonuçlar 3 sn'de bir yenilenir.
