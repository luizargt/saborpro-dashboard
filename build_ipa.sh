#!/bin/bash

# =============================================================================
# Build de Sabor Manager para iOS, CON Shorebird.
#
# Uso: ./build_ipa.sh
#
# QUE DEJA
#   build/ios/ipa-shorebird/*.ipa   -> esto se sube a App Store Connect
#
# POR QUE EXPORTA EL IPA APARTE
# `shorebird release ios` arma bien el archive, pero al exportar el IPA usa un
# ExportOptions que genera Flutter, no el del proyecto, y falla con:
#   "requires a provisioning profile with the Push Notifications feature"
# El perfil SI tiene push; lo que falta en ese plist generado es el mapeo
# manual bundle -> perfil. Por eso el archive se exporta acá con
# ios/ExportOptions.plist, que sí lo trae. El binario es el MISMO que Shorebird
# registró, así que el release sigue siendo parcheable.
#
# OJO CON PUSH: el entitlement de Release apunta a `production`
# (ios/Runner/RunnerRelease.entitlements) porque un perfil de App Store solo
# acepta eso. El de Debug sigue en `development`, que es lo que necesitan las
# pruebas en dispositivo. Son dos archivos a propósito: con uno solo, o no
# compila para la tienda o no llegan los avisos en desarrollo.
#
# DESPUES, para mandar un arreglo de solo Dart sin pasar por Apple:
#   shorebird patch --platforms=ios --release-version=<version>
# =============================================================================

set -e

command -v shorebird >/dev/null 2>&1 || {
  echo "Falta shorebird. Instalalo: https://docs.shorebird.dev"
  exit 1
}

VERSION="$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d ' ')"
SALIDA="build/ios/ipa-shorebird"

echo "Construyendo Sabor Manager $VERSION para iOS con Shorebird..."
echo "(el paso de Xcode tarda unos 13 minutos)"
echo ""

# Falla al exportar el IPA, pero deja el archive y registra el release: por eso
# no se corta el script acá.
shorebird release ios --no-confirm "$@" || true

ARCHIVE="build/ios/archive/Runner.xcarchive"
[ -d "$ARCHIVE" ] || { echo "No se generó el archive. Revisá la salida de arriba."; exit 1; }

echo ""
echo "Exportando el IPA con la firma del proyecto..."
rm -rf "$SALIDA"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist ios/ExportOptions.plist \
  -exportPath "$SALIDA"

IPA="$(ls "$SALIDA"/*.ipa 2>/dev/null | sed -n '1p')"
[ -n "$IPA" ] || { echo "No se generó el IPA."; exit 1; }

echo ""
echo "✅ IPA: $IPA"
echo ""
echo "Comprobación rápida de lo que se va a subir:"
TMP="$(mktemp -d)"
unzip -q "$IPA" -d "$TMP"
APP="$TMP/Payload/Runner.app"
echo "   versión : $(plutil -extract CFBundleShortVersionString raw "$APP/Info.plist") ($(plutil -extract CFBundleVersion raw "$APP/Info.plist"))"
echo "   bundle  : $(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")"
echo "   push    : $(codesign -d --entitlements :- "$APP" 2>/dev/null | plutil -extract aps-environment raw - 2>/dev/null)"
echo "   perfil  : $(security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null | plutil -extract Name raw - 2>/dev/null)"
if [ -f "$APP/Frameworks/App.framework/flutter_assets/shorebird.yaml" ]; then
  echo "   parches : sí, lleva el motor de Shorebird"
else
  echo "   parches : NO — este binario no podrá recibir arreglos"
fi
rm -rf "$TMP"
echo ""
echo "Subilo con Transporter, o desde Xcode: Window > Organizer > Distribute App."
