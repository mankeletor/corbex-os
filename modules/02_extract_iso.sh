#!/bin/bash
# modules/02_extract_iso.sh

echo "💿 [Módulo 02] Extrayendo ISO original..."

# Cargar configuración if not loaded
[ -z "$ISO_HOME" ] && source ./config.env

# Limpiar trabajo anterior
echo "   Limpiando $WORKDIR..."
rm -rf "$WORKDIR" 2>/dev/null
mkdir -p "$ISO_HOME"

# Montar y copiar
echo "   Montando y copiando archivos de la ISO (esto puede tardar)..."
sudo mkdir -p /mnt/original_iso
sudo mount -o loop "$ISO_ORIGINAL" /mnt/original_iso
rsync -a /mnt/original_iso/ "$ISO_HOME/"
sudo umount /mnt/original_iso
sudo rmdir /mnt/original_iso

echo "✅ ISO extraída en $ISO_HOME"
