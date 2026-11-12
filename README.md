# Soap Opera Studio — Flutter arayüz prototipi

Mock veriyle çalışan mobil arayüz. Henüz backend yok; amaç haftalık demoda
çalışan ekranları göstermek. Sadece Flutter'ın kendi paketlerini kullanır.

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
