#!/bin/bash
flutter build apk --release
cp build/app/outputs/apk/release/SPGerencia-*.apk build/app/outputs/flutter-apk/SPGerencia.apk
echo "✅ APK lista: build/app/outputs/flutter-apk/SPGerencia.apk"
