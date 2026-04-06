#!/bin/bash
# modules/01_check_deps.sh
set -euo pipefail

echo "📋 [Módulo 01] Verificando dependencias y rutas..."

# Cargar configuración si no está cargada
# Carga de configuración corregida
if [ -z "${ISO_ORIGINAL:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$SCRIPT_DIR/../config.env" ]; then
        source "$SCRIPT_DIR/../config.env"
    fi
fi

# 1. Verificar comandos necesarios
for cmd in cpio gzip xorriso curl rsync wget awk sed dpkg-scanpackages apt-ftparchive mcopy mdel; do
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
