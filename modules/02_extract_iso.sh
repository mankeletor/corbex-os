#!/bin/bash
# modules/02_extract_iso.sh
set -euo pipefail

echo "💿 [Módulo 02] Extrayendo ISO original..."

source "$(dirname "$0")/_common.sh"

# Limpiar trabajo anterior
echo "   Limpiando $WORKDIR..."
rm -rf "$WORKDIR" 2>/dev/null
mkdir -p "$ISO_HOME"

# Extracción usando xorriso (no requiere sudo mount)
echo "   Extrayendo archivos de la ISO con xorriso..."
xorriso -osirrox on -indev "$ISO_ORIGINAL" -extract / "$ISO_HOME"

if [ $? -ne 0 ] || [ ! -d "$ISO_HOME/boot" ]; then
    echo "❌ Error fatal: La extracción de la ISO falló o está incompleta."
    exit 1
fi

# Extraer archivos de booteo críticos
echo "   Extrayendo metadatos de booteo (isohdpfx.bin y efi.img)..."
mkdir -p "$ISO_HOME/boot/grub" 2>/dev/null

# Extraer el MBR (isohdpfx.bin) de los primeros 432 bytes
dd if="$ISO_ORIGINAL" of="$ISO_HOME/boot/isolinux/isohdpfx.bin" bs=1 count=432 status=none

# Extraer la partición EFI (efi.img)
# Según reporte previo el offset es 1148928 sectores de 512 bytes
dd if="$ISO_ORIGINAL" of="$ISO_HOME/boot/grub/efi.img" bs=512 skip=1148928 count=65000 status=none

echo "✅ ISO extraída correctamente en $ISO_HOME"
