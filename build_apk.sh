#!/bin/bash
flutter build apk --release
cp build/app/outputs/apk/release/Dashboard-*.apk build/app/outputs/flutter-apk/Dashboard.apk
echo "✅ APK lista: build/app/outputs/flutter-apk/Dashboard.apk"
