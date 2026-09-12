#!/bin/bash

# =============================================================================
# Build de Sabor Manager para Android, CON Shorebird.
#
# Uso: ./build_apk.sh
#
# POR QUE CON SHOREBIRD Y NO CON `flutter build`
# Un binario compilado con `flutter build` no lleva dentro el motor de
# actualizacion, y despues NO hay forma de mandarle un arreglo sin pasar por la
# revision de Google. El 2026-09-12 se descubrio asi: habia un arreglo listo en
# Dart, parcheable en teoria, y no se pudo mandar porque el unico release
# registrado en Shorebird era 1.1.0+12, de cuatro versiones atras. Todo lo
# publicado despues se habia armado con `flutter build apk`.
#
# QUE DEJA
#   build/app/outputs/bundle/release/app-release.aab   -> esto va a Play Store
#   build/app/outputs/shorebird-apk/universal.apk      -> para instalar a mano
#
# DESPUES, para mandar un arreglo de solo Dart sin pasar por la tienda:
#   ./patch_apk.sh
# =============================================================================

set -e

command -v shorebird >/dev/null 2>&1 || {
  echo "Falta shorebird. Instalalo: https://docs.shorebird.dev"
  exit 1
}

VERSION="$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d ' ')"

echo "Construyendo Sabor Manager $VERSION con Shorebird..."
echo "(Shorebird compila con SU version de Flutter, no con la del sistema)"
echo ""

shorebird release android "$@"

echo ""
echo "Generando el APK desde ese mismo release..."
shorebird releases get-apks --release-version "$VERSION"

DESTINO="build/app/outputs/shorebird-apk/SaborManager-$VERSION-shorebird.apk"
if [ -f build/app/outputs/shorebird-apk/universal.apk ]; then
  cp build/app/outputs/shorebird-apk/universal.apk "$DESTINO"
  echo ""
  echo "✅ APK: $DESTINO"
fi
echo "✅ AAB para Play Store: build/app/outputs/bundle/release/app-release.aab"
echo ""
echo "OJO: en build/app/outputs/shorebird-apk/ pueden quedar APKs de builds"
echo "viejos con su version en el nombre. Fijate en la fecha antes de subir:"
ls -la build/app/outputs/shorebird-apk/*.apk 2>/dev/null | awk '{print "   ", $6, $7, $8, $9}'
