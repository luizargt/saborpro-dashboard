#!/bin/bash

# =============================================================================
# Manda un arreglo de Sabor Manager a los teléfonos SIN pasar por Play Store.
#
# Uso: ./patch_apk.sh [version-del-release]
#      ./patch_apk.sh            -> parchea el release de la version del pubspec
#      ./patch_apk.sh 1.1.5+17   -> parchea ese release en concreto
#
# QUE SE PUEDE MANDAR ASI
#   Solo codigo Dart. Nada de esto entra en un parche:
#     - dependencias nuevas en pubspec.yaml (plugins con codigo nativo)
#     - cambios en android/ o ios/
#     - assets nuevos
#     - cambiar de version de Flutter
#   Si tocaste algo de eso, hay build nuevo y tienda. No hay atajo.
#
# CONDICION: el telefono tiene que tener instalado un binario hecho con
# `shorebird release`. Uno hecho con `flutter build` no recibe parches nunca,
# por mas que el codigo sea parcheable.
# =============================================================================

set -e

command -v shorebird >/dev/null 2>&1 || {
  echo "Falta shorebird. Instalalo: https://docs.shorebird.dev"
  exit 1
}

VERSION="${1:-$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d ' ')}"

echo "Preparando parche para el release $VERSION..."
echo ""

# Que no se cuele en un parche algo que un parche no puede llevar.
if ! git diff --quiet HEAD -- pubspec.yaml android ios 2>/dev/null; then
  echo "⚠️  OJO: hay cambios sin commitear en pubspec.yaml, android/ o ios/."
  echo "   Un parche NO los lleva. Si el arreglo depende de eso, necesitas"
  echo "   build nuevo y subirlo a la tienda."
  echo ""
fi

shorebird patch --platforms=android --release-version="$VERSION"

echo ""
echo "Listo. Los telefonos con $VERSION instalada lo bajan solo al abrir la app."
echo "Los que tengan una version anterior siguen igual hasta que actualicen."
