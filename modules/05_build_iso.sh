#!/bin/bash
# modules/05_build_iso.sh
set -euo pipefail

echo "💿 [Módulo 05] Reconstruyendo ISO final con Xorriso..."

# Cargar configuración
# Carga de configuración corregida
if [ -z "$ISO_ORIGINAL" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../config.env"
fi

# Nombre del archivo ISO final
ISO_FILENAME="${ISO_PREFIX}-$(date +%Y%m%d_%H%M).iso"

# Construcción
xorriso -as mkisofs \
    -r -V "$ISO_VOLID" \
    -o "$WORKDIR/$ISO_FILENAME" \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -c boot/isolinux/boot.cat \
    -b boot/isolinux/isolinux.bin \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    "$ISO_HOME"

if [ $? -eq 0 ]; then
    echo "✅ ISO creada con éxito: $ISO_FILENAME ($(du -sh "$WORKDIR/$ISO_FILENAME" | cut -f1))" 
    cd "$WORKDIR"
    md5sum "$ISO_FILENAME" > "${ISO_FILENAME}.md5"
    echo "✅ Suma MD5 generada"
else
    echo "❌ Error fatal en la creación de la ISO"
    exit 1
fi

echo "🔍 Verificando booteo MBR..."
file "$WORKDIR/$ISO_FILENAME" | grep -q "boot sector" && echo "✅ Estructura de booteo detectada"

echo "🎉 ¡CONSTRUCCIÓN FINALIZADA!"
echo "📀 Archivo: $WORKDIR/$ISO_FILENAME"
