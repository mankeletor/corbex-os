#!/bin/bash
# modules/05_build_iso.sh
set -euo pipefail

echo "💿 [Módulo 05] Reconstruyendo ISO final con Xorriso..."

source "$(dirname "$0")/_common.sh"

# Nombre del archivo ISO final
ISO_FILENAME="${ISO_PREFIX}-$(date +%Y%m%d_%H%M).iso"

# 1. Actualizar isolinux.cfg (Añadir entrada CorbexOS sin destruir original)
echo "   Actualizando isolinux.cfg para incluir preseed..."

cat $BASE_DIR/templates/isolinux.cfg > "$ISO_HOME/boot/isolinux/isolinux.cfg"

# 1.5 Inyectar config Syslinux-EFI dedicada en el efi.img
# IMPORTANTE: No usar isolinux.cfg (BIOS) aquí — Syslinux-EFI tiene otra cadena:
#   BOOTX64.EFI → EFI/BOOT/syslinux.cfg → /boot/isolinux/syslinux.cfg  ← reemplazamos esto
# El EFI/BOOT/syslinux.cfg NO se toca (tiene el redirect correcto a /boot/isolinux).
if command -v mcopy > /dev/null 2>&1; then
    echo "   Actualizando syslinux.cfg UEFI dentro de efi.img con template EFI dedicado..."
    efi_img="$ISO_HOME/boot/grub/efi.img"
    mdel -i "$efi_img" ::/boot/isolinux/syslinux.cfg >/dev/null 2>&1 || true
    mcopy -i "$efi_img" "$BASE_DIR/templates/syslinux_efi.cfg" ::/boot/isolinux/syslinux.cfg
    echo "   ✅ syslinux_efi.cfg inyectado en efi.img"
else
    echo "⚠️ ADVERTENCIA: 'mtools' no está instalado. No se pudo parchear el booteo UEFI."
fi
# 2. Construcción con Xorriso
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
