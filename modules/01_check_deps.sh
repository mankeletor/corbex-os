#!/bin/bash
# modules/01_check_deps.sh

echo "📋 [Módulo 01] Verificando dependencias y rutas..."

# Cargar configuración si no está cargada
[ -z "$ISO_ORIGINAL" ] && source ./config.env

# 1. Verificar comandos necesarios
for cmd in cpio gzip xorriso curl rsync wget awk sed dpkg-scanpackages; do
    if ! command -v $cmd &> /dev/null; then
        echo "❌ Error: $cmd no está instalado. Instalalo con: apt install $cmd"
        exit 1
    fi
done

# 2. Verificar archivos críticos de isolinux
if [ ! -f "/usr/lib/ISOLINUX/isohdpfx.bin" ]; then
    echo "❌ Error: /usr/lib/ISOLINUX/isohdpfx.bin no encontrado. Instalá isolinux."
    exit 1
fi

# 3. Verificar existencia de ISOs base
if [ ! -f "$ISO_ORIGINAL" ]; then
    echo "❌ Error: No se encuentra ISO original en $ISO_ORIGINAL"
    exit 1
fi

if [ ! -f "$POOL1_ISO" ]; then
    echo "❌ Error: No se encuentra la ISO de pool1 en $POOL1_ISO"
    exit 1
fi

echo "✅ Entorno validado correctamente"
