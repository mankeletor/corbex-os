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

# 1. Actualizar isolinux.cfg (Añadir entrada ESFP Córdoba sin destruir original)
echo "   Actualizando isolinux.cfg para incluir preseed..."
sed -i '$d' "$ISO_HOME/boot/isolinux/isolinux.cfg"
head -4 $BASE_DIR/templates/isolinux.cfg >> "$ISO_HOME/boot/isolinux/isolinux.cfg" 

# 2. Construcción con Xorriso Híbrido Robusto (v0.99rc24)
echo "   Ejecutando Xorriso con parámetros de booteo de la ISO original..."
xorriso -as mkisofs -r -J -joliet-long \
  -isohybrid-mbr "$ISO_HOME/boot/isolinux/isohdpfx.bin" \
  -v -V "$ISO_VOLID" \
  -o "$WORKDIR/$ISO_FILENAME" \
  -c boot/isolinux/boot.cat \
  -b boot/isolinux/isolinux.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
  -isohybrid-gpt-basdat \
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
