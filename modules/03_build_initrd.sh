#!/bin/bash
# modules/03_build_initrd.sh

echo "📦 [Módulo 03] Modificando Initrd e Inyectando archivos..."

# Cargar configuración
[ -z "$ISO_HOME" ] && source ./config.env

# 1. Cargar paquetes desde pkgs.txt
echo "   Cargando paquetes desde $PKGS_FILE..."
PAQUETES=()
if [ -f "$PKGS_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ -z "$line" || "$line" == Estado=* || "$line" == Err?=* || "$line" == Nombre ]]; then continue; fi
        pkg=$(echo "$line" | awk '{ if ($1 ~ /^[a-z][a-z]$/) print $2; else print $1; }' | sed 's/:.*//')
        [ -n "$pkg" ] && [[ ! "$pkg" =~ ^[./] ]] && PAQUETES+=("$pkg")
    done < "$PKGS_FILE"
else
    echo "⚠️ pkgs.txt no encontrado, usando lista mínima"
    PAQUETES=(mate-desktop-environment-core mate-terminal network-manager firmware-linux-nonfree)
fi

# Añadir obligatorios y corregir faltantes reportados
for critical in code mate-menu mate-desktop-environment-extras mate-applets multiload-ng bash-completion sudo; do
    if [[ ! " ${PAQUETES[@]} " =~ " $critical " ]]; then
        echo "   → Asegurando paquete crítico: $critical"
        PAQUETES+=("$critical")
    fi
done

# 2. Descomprimir Initrd
local_initrd="$ISO_HOME/boot/isolinux/initrd.gz"
[ ! -f "${local_initrd}.original" ] && cp "$local_initrd" "${local_initrd}.original"

mkdir -p "$WORKDIR/temp_initrd"
cd "$WORKDIR/temp_initrd"
zcat "$local_initrd" | cpio -idmv > /dev/null 2>&1

# 3. Inyectar archivos (desde templates y scripts_aux)
echo "   Inyectando preseed.cfg, postinst_final.sh, rc.conf y pkgs.txt..."
cp "../../templates/preseed.cfg" ./preseed.cfg
cp "../../scripts_aux/postinst_final.sh" ./postinst.sh
cp "../../templates/rc.conf" ./rc.conf
cp "../../pkgs.txt" ./pkgs.txt

# --- NUEVO: Script de intervención radical (finish-install) ---
echo "   Creando script de intervención radical /usr/lib/finish-install.d/99esfp-custom..."
mkdir -p usr/lib/finish-install.d
cat > usr/lib/finish-install.d/99esfp-custom << 'EOF'
#!/bin/sh
# 99esfp-custom - Inyectado por ESFP Córdoba Modular v0.12.1
# Asegura la instalación forzada de paquetes antes del primer booteo.
echo "🔥 [Radical] Forzando instalación de paquetes desde pkgs.txt..."
if [ -f /target/root/pkgs.txt ]; then
    LISTA_PKGS=$(grep -vE "^(Estado|Err?|Nombre| |$)" /target/root/pkgs.txt | awk '{print $1}' | tr '\n' ' ')
    chroot /target apt-get update -qq
    chroot /target apt-get install -y --no-install-recommends $LISTA_PKGS
else
    echo "⚠️ /target/root/pkgs.txt no encontrado."
fi
EOF
chmod +x usr/lib/finish-install.d/99esfp-custom

# 4. Actualizar preseed con la lista de paquetes (Sincronizar para asegurar limpieza)
PKGS_STRING=$(echo "${PAQUETES[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')
sed -i "s/^d-i pkgsel\/include string .*/d-i pkgsel\/include string bash-completion sudo $PKGS_STRING/g" ./preseed.cfg

# 5. Reempaquetar
echo "   Reempaquetando Initrd..."
find . | cpio -H newc -o | gzip -9 > "$WORKDIR/initrd_nuevo.gz"

mv "$WORKDIR/initrd_nuevo.gz" "$local_initrd"
cd "$WORKDIR"
rm -rf "$WORKDIR/temp_initrd"

echo "✅ Initrd actualizado e inyectado"
