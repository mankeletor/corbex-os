#!/bin/bash
# modules/03_build_initrd.sh
set -euo pipefail

echo "📦 [Módulo 03] Modificando Initrd e Inyectando archivos..."

source "$(dirname "$0")/_common.sh"

# 1. Cargar paquetes desde pkgs_install.txt (Lista unificada pre-procesada)
PKGS_INSTALL_FILE="$BASE_DIR/pkgs_install.txt"
echo "   Cargando paquetes desde $PKGS_INSTALL_FILE..."
PAQUETES=()
if [ -f "$PKGS_INSTALL_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        # Saltar comentarios y líneas vacías
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        
        # Extraer nombre del paquete
        pkg=$(echo "$line" | awk '{print $1}' | sed 's/:.*//')
        
        # Validación básica de nombre de paquete
        if [[ "$pkg" =~ ^[a-z0-9][a-z0-9+.-]+$ ]]; then
            PAQUETES+=("$pkg")
        fi
    done < "$PKGS_INSTALL_FILE"
else
    echo "❌ Error: $PKGS_INSTALL_FILE no encontrado. Ejecutá el módulo 04 primero."
    exit 1
fi

# Asegurar paquetes base críticos
for critical in mate-desktop-environment-core mate-terminal \
network-manager firmware-linux-nonfree bash-completion sudo wpasupplicant \
wireless-tools iw rfkill curl rdate; do
    if [[ ! " ${PAQUETES[@]} " =~ " $critical " ]]; then
        PAQUETES+=("$critical")
    fi
done

# 2. Preparar el Payload a Inyectar (Método Overlay)
# Usamos método overlay: mini initrd con nuestra inyección concatenado al final.

local_initrd="$ISO_HOME/boot/isolinux/initrd.gz"
[ ! -f "${local_initrd}.original" ] && cp "$local_initrd" "${local_initrd}.original"

mkdir -p "$WORKDIR/payload_initrd"
cd "$WORKDIR/payload_initrd"

# 3. Preparar archivos críticos
echo "   Preparando preseed, postinst, rc.conf y listas de paquetes para el Overlay..."
cp "$BASE_DIR/preseed.cfg" ./preseed.cfg
cp "$BASE_DIR/scripts_aux/postinst_final.sh" ./postinst.sh
cp "$BASE_DIR/templates/rc.conf" ./rc.conf
cp "$BASE_DIR/templates/corbex.dconf" ./corbex.dconf
cp "$BASE_DIR/pkgs_install.txt" ./pkgs_install.txt
cp "$BASE_DIR/modules/04.5_build_source.sh" corbex-build-sources.sh
chmod +x corbex-build-sources.sh

# 🔥 DUAL-INJECT: Copiamos todo esto directamente a la raíz de la ISO
cp ./postinst.sh "$ISO_HOME/postinst.sh"
cp ./rc.conf "$ISO_HOME/rc.conf"
cp ./corbex.dconf "$ISO_HOME/corbex.dconf"
cp ./pkgs_install.txt "$ISO_HOME/pkgs_install.txt"
cp ./corbex-build-sources.sh "$ISO_HOME/corbex-build-sources.sh"

# Script de intervención radical (finish-install)
echo "   Configurando ejecución radical en finish-install..."
mkdir -p usr/lib/finish-install.d
cat > usr/lib/finish-install.d/99corbex-custom << 'EOF'
#!/bin/sh
# 99corbex-custom - Inyectado por CorbexOS Modular
echo "🔥 [Radical] Asegurando persistencia de scripts en /target..."
cp /postinst.sh /target/root/postinst.sh
chmod +x /target/root/postinst.sh
EOF
chmod +x usr/lib/finish-install.d/99corbex-custom

# Actualizar preseed con la lista "Cerebro"
PKGS_STRING=$(echo "${PAQUETES[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')
echo "   Inyectando paquetes: $PKGS_STRING"
sed -i "s/__PAQUETES__/$PKGS_STRING/g" ./preseed.cfg

# 🔥 DUAL-INJECT: Copiar el preseed procesado también al root de la ISO
# Esto asegura que el instalador lo encuentre aun si la concatenación del initrd falla en UEFI.
cp ./preseed.cfg "$ISO_HOME/preseed.cfg"
echo "   ✅ Preseed fallback copiado al root de la ISO"

# 4. Empaquetar el Payload
echo "   Empaquetando capa de Inyección..."
find . | cpio -H newc -o 2>/dev/null | gzip -9 > "$WORKDIR/inyeccion.cpio.gz"

# 5. Concatenar (BIOS)
echo "   Generando de forma segura el Initrd BIOS..."
cat "${local_initrd}.original" "$WORKDIR/inyeccion.cpio.gz" > "$local_initrd"

cd "$WORKDIR"
rm -rf "$WORKDIR/payload_initrd"

echo "   ✅ Initrd principal (BIOS) inyectado exitosamente"

# ==============================================================
# 🔥 MAGIA UEFI: Concatenar el mismo payload en el initrd.gz del EFI
# ==============================================================
echo "   [UEFI] Inyectando configuraciones en el initrd.gz integrado dentro de efi.img..."

efi_img="$ISO_HOME/boot/grub/efi.img"

if command -v mcopy > /dev/null 2>&1; then
    # Sacamos el initrd original del FAT
    mcopy -i "$efi_img" ::/boot/isolinux/initrd.gz "$WORKDIR/initrd_efi.gz"

    # Concatenamos el initrd original del EFI con nuestra Inyección
    cat "$WORKDIR/initrd_efi.gz" "$WORKDIR/inyeccion.cpio.gz" > "$WORKDIR/initrd_efi_nuevo.gz"

    # Borramos el viejo del FAT y metemos el inyectado
    mdel -i "$efi_img" ::/boot/isolinux/initrd.gz
    mcopy -i "$efi_img" "$WORKDIR/initrd_efi_nuevo.gz" ::/boot/isolinux/initrd.gz

    rm -f "$WORKDIR/initrd_efi.gz" "$WORKDIR/initrd_efi_nuevo.gz"
    echo "   ✅ Initrd EFI (UEFI) inyectado exitosamente con método Overlay"
else
    echo "⚠️ ADVERTENCIA: 'mtools' no está instalado. No se pudo parchear el booteo UEFI."
    echo "Por favor instale mtools con: sudo apt install mtools"
fi

rm -f "$WORKDIR/inyeccion.cpio.gz"
echo "✅ Todos los Initrds fueron actualizados"