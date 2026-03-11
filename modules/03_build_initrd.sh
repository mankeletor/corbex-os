#!/bin/bash
# modules/03_build_initrd.sh
set -euo pipefail

echo "📦 [Módulo 03] Modificando Initrd e Inyectando archivos..."

# Cargar configuración
# Carga de configuración corregida
if [ -z "$ISO_ORIGINAL" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../config.env"
fi

# 1. Cargar paquetes desde pkgs_manual.txt (Selección manual para preseed)
echo "   Cargando paquetes desde $PKGS_MANUAL_FILE..."
PAQUETES=()
if [ -f "$PKGS_MANUAL_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        # Saltar comentarios y líneas vacías
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        
        # Extraer nombre del paquete (asumiendo lista simple de apt-mark showmanual)
        pkg=$(echo "$line" | awk '{print $1}' | sed 's/:.*//')
        
        # Validación básica de nombre de paquete
        if [[ "$pkg" =~ ^[a-z0-9][a-z0-9+.-]+$ ]]; then
            PAQUETES+=("$pkg")
        fi
    done < "$PKGS_MANUAL_FILE"
else
    echo "❌ Error: $PKGS_MANUAL_FILE no encontrado."
    exit 1
fi

# Asegurar paquetes base críticos
for critical in mate-desktop-environment-core mate-terminal network-manager firmware-linux-nonfree bash-completion sudo; do
    if [[ ! " ${PAQUETES[@]} " =~ " $critical " ]]; then
        PAQUETES+=("$critical")
    fi
done

# 2. Descomprimir Initrd
local_initrd="$ISO_HOME/boot/isolinux/initrd.gz"
[ ! -f "${local_initrd}.original" ] && cp "$local_initrd" "${local_initrd}.original"

mkdir -p "$WORKDIR/temp_initrd"
cd "$WORKDIR/temp_initrd"
if ! zcat "$local_initrd" | cpio -idmv > /dev/null 2>&1; then
    echo "❌ Error: No se pudo extraer el initrd. ¿Está corrupto el archivo?"
    exit 1
fi
echo "   ✅ Initrd extraído correctamente"

# 3. Inyectar archivos críticos
echo "   Inyectando preseed, postinst, rc.conf y listas de paquetes..."
cp "$BASE_DIR/preseed.cfg" ./preseed.cfg
cp "$BASE_DIR/scripts_aux/postinst_final.sh" ./postinst.sh
cp "$BASE_DIR/templates/rc.conf" ./rc.conf
cp "$BASE_DIR/templates/corbex.dconf" ./corbex.dconf
cp "$BASE_DIR/pkgs_manual.txt" ./pkgs_manual.txt

# --- NUEVO: Script de intervención radical (finish-install) ---
# Optimizado para RAM: solo lanza apt tras asegurar que el target tiene el repo local
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

# 4. Actualizar preseed con la lista "Cerebro" (PKGS_MANUAL)
PKGS_STRING=$(echo "${PAQUETES[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')
echo "   Inyectando paquetes: $PKGS_STRING"
sed -i "s/__PAQUETES__/$PKGS_STRING/g" ./preseed.cfg

# 5. Reempaquetar
echo "   Reempaquetando Initrd (Multi-threading: $THREADS)..."
if command -v pigz > /dev/null 2>&1; then
    find . | cpio -H newc -o | pigz -p "$THREADS" -9 > "$WORKDIR/initrd_nuevo.gz"
else
    find . | cpio -H newc -o | gzip -9 > "$WORKDIR/initrd_nuevo.gz"
fi

mv "$WORKDIR/initrd_nuevo.gz" "$local_initrd"
cd "$WORKDIR"
rm -rf "$WORKDIR/temp_initrd"

echo "✅ Initrd actualizado e inyectado"