#!/bin/bash
# modules/04_repo_local.sh
# Lógica Complementaria Robusta v0.99rc25
set -euo pipefail

# Cargar configuración y asegurar BASE_DIR
if [ -z "${BASE_DIR:-}" ]; then
    BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

if [ -f "$BASE_DIR/config.env" ]; then
    source "$BASE_DIR/config.env"
else
    echo "❌ Error: config.env no encontrado en $BASE_DIR"
    exit 1
fi

# Redirección de logs (Cerebro v0.99rc25)
# Usar WORKDIR de config.env o fallback al directorio actual
WORKDIR="${WORKDIR:-$BASE_DIR/custom_esfp}"
PKG_CACHE="$BASE_DIR/pkg_cache"
LOG_FILE="$WORKDIR/logs/04_repo_local.log"
WARN_LOG="$WORKDIR/logs/warnings.log"
mkdir -p "$WORKDIR/logs" "$PKG_CACHE"
exec > >(tee -a "$LOG_FILE") 2>&1

# Manejo de parámetros
CLEAN_MODE=false
for arg in "$@"; do
    if [ "$arg" == "--clean" ]; then
        CLEAN_MODE=true
        break
    fi
done

if [ "$CLEAN_MODE" = true ]; then
    echo "[Clean] Vaciando caché de paquetes ($PKG_CACHE)..."
    # Borrar solo archivos .deb para no romper el directorio si está montado o algo similar
    find "$PKG_CACHE" -name "*.deb" -type f -delete
fi

# Optimización de hilos (Max segura)
CPU_COUNT=$(nproc)
THREADS=$((CPU_COUNT + 1))
[ "$THREADS" -gt 8 ] && THREADS=8
echo "   Utilizando $THREADS hilos para procesamiento paralelo."

# --- CONFIGURACIÓN DE SANDBOX APT (Multi-distro support) ---
echo "   Configurando entorno APT aislado..."
APT_SANDBOX="$WORKDIR/apt-temp"
# Estructura profunda para evitar errores de APT
mkdir -p "$APT_SANDBOX/var/lib/apt/lists/partial"
mkdir -p "$APT_SANDBOX/var/cache/apt/archives/partial"
mkdir -p "$APT_SANDBOX/etc/apt/preferences.d"
mkdir -p "$APT_SANDBOX/var/log/apt"

SOURCES_OUTPUT=$("$BASE_DIR/modules/3.5_build_source.sh" "dev1mir.registrationsplus.net") || true
if [ -z "$SOURCES_OUTPUT" ]; then
    echo "⚠️ Advertencia: 3.5_build_source.sh no generó salida. Usando sources.list manual."
    SOURCES_OUTPUT="deb http://dev1mir.registrationsplus.net/devuan/merged ${RELEASE:-excalibur} main contrib non-free non-free-firmware"
fi
echo "$SOURCES_OUTPUT" > "$APT_SANDBOX/etc/apt/sources.list"

# Inyectar llaves GPG del host para evitar errores de validación
mkdir -p "$APT_SANDBOX/etc/apt/trusted.gpg.d"
if [ -f /etc/apt/trusted.gpg ]; then
    cp /etc/apt/trusted.gpg "$APT_SANDBOX/etc/apt/trusted.gpg" || true
fi
if [ -d /etc/apt/trusted.gpg.d ]; then
    cp -r /etc/apt/trusted.gpg.d/* "$APT_SANDBOX/etc/apt/trusted.gpg.d/" || true
fi

cat > "$APT_SANDBOX/apt.conf" << EOF
Dir "$APT_SANDBOX";
Dir::State "$APT_SANDBOX/var/lib/apt";
Dir::Cache "$APT_SANDBOX/var/cache/apt";
Dir::Etc "$APT_SANDBOX/etc/apt";
Dir::Log "$APT_SANDBOX/var/log/apt";
# Configuraciones para Sandbox sin GPG (si fallan las llaves)
Acquire::AllowInsecureRepositories "true";
Acquire::AllowDowngradeToInsecureRepositories "true";
Acquire::Check-Valid-Until "false";
APT::Get::AllowUnauthenticated "true";
Acquire::https::Verify-Peer "false";
APT::Architecture "amd64";
EOF

echo "   Sincronizando índices de Devuan en el sandbox..."
# Forzar actualización ignorando cualquier restricción de seguridad del host
apt-get -c "$APT_SANDBOX/apt.conf" update -o APT::Get::AllowUnauthenticated=true -o Acquire::AllowInsecureRepositories=true -qq || true

# 0. Cargar y Validar paquetes (Usando lista manual como semilla)
echo "   Cargando paquetes base desde $PKGS_MANUAL_FILE..."
PAQUETES_SEMILLA=()
if [ -f "$PKGS_MANUAL_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        pkg=$(echo "$line" | awk '{print $1}' | sed 's/:.*//')
        if [[ "$pkg" =~ ^[a-z0-9][a-z0-9+.-]+$ ]]; then
            PAQUETES_SEMILLA+=("$pkg")
        fi
    done < "$PKGS_MANUAL_FILE"
else
    echo "❌ Error: $PKGS_MANUAL_FILE no encontrado."
    exit 1
fi

# Inyección de paquetes CRÍTICOS (Declarativo)
PAQUETES_CRITICOS=(
    sudo
    wget
    net-tools
    bash-completion
    libc6
    libgcc-s1
    libeudev1
    mate-menu
    mate-tweak
    mate-desktop-environment-extras
    mate-applets
    flatpak
    geogebra
    curl
    vlc
    vlc-plugin-base
    chromium
    network-manager
    wpasupplicant
    wireless-tools
    firmware-linux-nonfree
    intel-microcode
    xserver-xorg-video-intel
    va-driver-all
    usb-modeswitch
    task-laptop
)
PAQUETES_SEMILLA+=("${PAQUETES_CRITICOS[@]}")

# 0.1 Resolución de Dependencias Recursivas (Cerebro v0.99rc27)
echo "   Resolviendo dependencias recursivas mediante simulación APT..."
# Extraer solo los nombres de paquetes que APT planea instalar
PAQUETES_LISTA_COMPLETA=$(apt-get -c "$APT_SANDBOX/apt.conf" --simulate install "${PAQUETES_SEMILLA[@]}" 2>/dev/null | grep "^Inst " | awk '{print $2}' | sort -u || true)

if [ -z "$PAQUETES_LISTA_COMPLETA" ]; then
    echo "⚠️ Advertencia: APT no pudo resolver dependencias. Usando solo lista manual."
    mapfile -t PAQUETES < <(printf "%s\n" "${PAQUETES_SEMILLA[@]}" | sort -u)
else
    mapfile -t PAQUETES <<< "$PAQUETES_LISTA_COMPLETA"
fi
# 0.2 Generación de pkgs_offline.txt (Refactorizado)
echo "   Generando pkgs_offline.txt consolidado..."

if [ -n "$PAQUETES_LISTA_COMPLETA" ]; then
    # Volcamos la lista resuelta al archivo, un paquete por línea
    echo "$PAQUETES_LISTA_COMPLETA" | tr ' ' '\n' | sort -u > "$BASE_DIR/pkgs_offline.txt"
    echo "✅ pkgs_offline.txt actualizado con $(wc -l < "$BASE_DIR/pkgs_offline.txt") paquetes (base + críticos + dependencias)."
else
    # Fallback: Si APT falló, al menos guardamos la semilla para no quedar en cero
    echo "⚠️ Usando PAQUETES_SEMILLA como fallback para pkgs_offline.txt"
    printf "%s\n" "${PAQUETES_SEMILLA[@]}" | sort -u > "$BASE_DIR/pkgs_offline.txt"
fi

sed -i '/^$/d' "$BASE_DIR/pkgs_offline.txt"

#echo "   ✅ Total de paquetes únicos a procesar (manual + dependencias): ${#PAQUETES[@]}"

# Directorios
mkdir -p "$ISO_HOME/pool/local"
mkdir -p "$ISO_HOME/dists/excalibur/local/binary-amd64"

# 1. Identificar paquetes BASE
echo "   Indexando base Netinstall para de-duplicación..."
BASE_PKGS_FILE="$WORKDIR/base_packages.txt"
if [ -f "$ISO_HOME/dists/excalibur/main/binary-amd64/Packages" ]; then
    grep "^Package: " "$ISO_HOME/dists/excalibur/main/binary-amd64/Packages" | cut -d' ' -f2 | sort -u > "$BASE_PKGS_FILE"
else
    touch "$BASE_PKGS_FILE"
fi

# 2. Extraer e Indexar Pool1
EXTRACT_DIR="$WORKDIR/pool1_files"
POOL1_INDEX="$WORKDIR/pool1_index.txt"
echo "   Extrayendo Pool1.iso..."
rm -rf "$EXTRACT_DIR" 2>/dev/null
mkdir -p "$EXTRACT_DIR"
xorriso -osirrox on -indev "$POOL1_ISO" -extract /pool "$EXTRACT_DIR" 2>/dev/null || { echo "❌ Error: Falló la extracción de $POOL1_ISO"; exit 1; }

# Crear índice de búsqueda rápida
find "$EXTRACT_DIR" -name "*.deb" -printf "%p\n" > "$POOL1_INDEX"
DEB_COUNT=$(wc -l < "$POOL1_INDEX")
echo "   ✅ Pool1 indexado ($DEB_COUNT paquetes)."

# 3. Procesamiento Paralelo Optimizado
export EXTRACT_DIR ISO_HOME BASE_PKGS_FILE POOL1_INDEX WARN_LOG APT_SANDBOX PKG_CACHE
process_pkg() {
    local pkg=$1
    local retries=2
    local count=0
    
    # 1. ¿Está en base? (Inmutabilidad estricta)
    if grep -q "^${pkg}$" "$BASE_PKGS_FILE"; then return 0; fi

    # 2. Buscar en índice de Pool1
    local DEB_PATH
    DEB_PATH=$(grep -m1 "/${pkg}_[0-9]" "$POOL1_INDEX" || true)
    
    if [ -n "$DEB_PATH" ] && [ -f "$DEB_PATH" ]; then
        cp "$DEB_PATH" "$ISO_HOME/pool/local/" || echo "❌ Error copiando $pkg desde Pool1" >> "$WARN_LOG"
    else
        # 3. Buscar en Cache persistente
        local CACHED_DEB
        CACHED_DEB=$(find "$PKG_CACHE" -maxdepth 1 -name "${pkg}_*.deb" -print -quit 2>/dev/null || true)
        if [ -n "$CACHED_DEB" ] && [ -f "$CACHED_DEB" ]; then
            cp "$CACHED_DEB" "$ISO_HOME/pool/local/" || echo "❌ Error copiando $pkg desde Cache" >> "$WARN_LOG"
        else
            # 4. Descarga con Sandbox APT y Re-intento
            while [ "$count" -le "$retries" ]; do
                # Descargar a cache primero con flags de ultra-compatibilidad
                if (cd "$PKG_CACHE" && apt-get -c "$APT_SANDBOX/apt.conf" download "$pkg" -o APT::Get::AllowUnauthenticated=true -o Acquire::AllowInsecureRepositories=true -qq 2>/dev/null); then
                    local NEW_DEB
                    NEW_DEB=$(find "$PKG_CACHE" -maxdepth 1 -name "${pkg}_*.deb" -print -quit 2>/dev/null || true)
                    if [ -n "$NEW_DEB" ]; then
                        cp "$NEW_DEB" "$ISO_HOME/pool/local/"
                        return 0
                    fi
                fi
                ((count++))
                [ "$count" -le "$retries" ] && sleep 1
            done
            echo "❌ No disponible tras $retries reintentos (Sandbox): $pkg" >> "$WARN_LOG"
        fi
    fi
}
export -f process_pkg

echo "   Iniciando copia/descarga paralela..."
printf "%s\n" "${PAQUETES[@]}" | xargs -I {} -P "$THREADS" bash -c 'process_pkg "$@"' _ {}

# 4. Generar Índices Apt
echo "   Generando índices de repositorio local..."
cd "$ISO_HOME"
dpkg-scanpackages -m pool/local /dev/null | gzip -9c > dists/excalibur/local/binary-amd64/Packages.gz
zcat dists/excalibur/local/binary-amd64/Packages.gz > dists/excalibur/local/binary-amd64/Packages

# Generar archivo Release con checksums MD5
echo "   Generando Release con checksums MD5..."
cat > "dists/excalibur/local/binary-amd64/Release" << EOF
Origin: Devuan ESFP Córdoba
Label: ESFP Córdoba Local Repo
Suite: excalibur
Codename: excalibur
Date: $(date -Ru)
Architectures: amd64
Components: local
Description: Paquetes Complementarios ESFP Córdoba

MD5Sum:
$(find "dists/excalibur/local/binary-amd64" -type f \( -name "Packages*" -o -name "Release" \) -printf "%P\n" | grep -v "^Release$" | while read -r f; do
    printf " %s %16d %s\n" "$(md5sum "dists/excalibur/local/binary-amd64/$f" | cut -d' ' -f1)" "$(stat -c%s "dists/excalibur/local/binary-amd64/$f")" "$f"
done)
SHA256:
$(find "dists/excalibur/local/binary-amd64" -type f \( -name "Packages*" -o -name "Release" \) -printf "%P\n" | grep -v "^Release$" | while read -r f; do
    printf " %s %16d %s\n" "$(sha256sum "dists/excalibur/local/binary-amd64/$f" | cut -d' ' -f1)" "$(stat -c%s "dists/excalibur/local/binary-amd64/$f")" "$f"
done)
EOF

rm -rf "$EXTRACT_DIR" "$APT_SANDBOX"
echo "✅ Módulo 04 finalizado exitosamente."
