# needed_files

Files the Flutter project needs that are not in `lib/`. Copy everything in this
folder into the project root (next to `pubspec.yaml`), keeping the folder layout:

```
needed_files/.metadata              -> .metadata
needed_files/analysis_options.yaml  -> analysis_options.yaml
needed_files/pubspec.lock           -> pubspec.lock   (same package versions for everyone)
needed_files/web/                   -> web/           (Flutter web: index.html, manifest, icons)
needed_files/test/widget_test.dart  -> test/widget_test.dart
```

Windows (PowerShell, in the project root):

```powershell
Copy-Item -Recurse -Force needed_files\* .
Copy-Item -Force needed_files\.metadata .
flutter pub get
flutter run -d chrome
```

macOS / Linux:

```bash
cp -R needed_files/. .
flutter pub get
flutter run -d chrome
```

Android / iOS folders are not included yet. To build for a phone, run once:
`flutter create . --platforms=android,ios` (it does not overwrite `lib/`).

No secrets are in this folder. Never add `.env` or any API key here.
