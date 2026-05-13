#!/bin/bash
# modules/01_check_deps.sh
set -euo pipefail

echo "📋 [Módulo 01] Verificando dependencias y rutas..."

source "$(dirname "$0")/_common.sh"

# 1. Verificar comandos necesarios
for cmd in cpio gzip xorriso curl rsync wget awk sed dpkg-scanpackages apt-ftparchive mcopy mdel rdate; do
    if ! command -v $cmd &> /dev/null; then
        echo "❌ Error: $cmd no está instalado."
        if [ "$cmd" = "dpkg-scanpackages" ]; then
            echo "   Instalalo con: apt install dpkg-dev"
        elif [ "$cmd" = "mcopy" ] || [ "$cmd" = "mdel" ]; then
            echo "   Instalalo con: apt install mtools"
        else
            echo "   Instalalo con: apt install $cmd"
        fi
        echo "💡 Tip: Instala 'pigz' para acelerar la construcción con multi-threading."
        exit 1
    fi
done

# Sincronización inicial del reloj (para evitar fallos SSL en curl/apt)
echo "   Sincronizando reloj con time-a.nist.gov..."
rdate -s time-a.nist.gov || echo "⚠️ Advertencia: No se pudo sincronizar el reloj. Verifique su conexión."

# 2. Verificar existencia de ISOs base
if [ ! -f "$ISO_ORIGINAL" ]; then
    echo "❌ Error: No se encuentra ISO original en $ISO_ORIGINAL"
    exit 1
fi

if [ ! -f "$POOL1_ISO" ]; then
    echo "❌ Error: No se encuentra la ISO de pool1 en $POOL1_ISO"
    exit 1
fi

echo "✅ Entorno validado correctamente"
