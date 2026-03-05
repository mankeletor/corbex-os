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

cat > "$APT_SANDBOX/etc/apt/sources.list" << EOF
deb [trusted=yes] http://deb.devuan.org/merged excalibur main contrib non-free non-free-firmware
deb [trusted=yes] http://deb.devuan.org/merged excalibur-updates main contrib non-free non-free-firmware
deb [trusted=yes] http://deb.devuan.org/merged excalibur-security main contrib non-free non-free-firmware
# Daedalus como fallback
deb [trusted=yes] http://deb.devuan.org/merged daedalus main contrib non-free non-free-firmware
EOF

# Inyectar llaves GPG del host para evitar errores de validación
mkdir -p "$APT_SANDBOX/etc/apt/trusted.gpg.d"
[ -f /etc/apt/trusted.gpg ] && cp /etc/apt/trusted.gpg "$APT_SANDBOX/etc/apt/trusted.gpg" || true
[ -d /etc/apt/trusted.gpg.d ] && cp -r /etc/apt/trusted.gpg.d/* "$APT_SANDBOX/etc/apt/trusted.gpg.d/" || true

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

# 0. Cargar y Validar paquetes (Usando lista manual para resolución)
echo "   Cargando y validando paquetes desde $PKGS_MANUAL_FILE..."
PAQUETES_RAW=()
if [ -f "$PKGS_MANUAL_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        [[ -z "$line" || "$line" =~ ^# || "$line" == Estado=* || "$line" == Err?=* || "$line" == Nombre ]] && continue
        pkg=$(echo "$line" | awk '{ if ($1 ~ /^[a-z][a-z]$/) print $2; else print $1; }' | sed 's/:.*//')
        
        # Validación Regex de nombre de paquete Debian
        if [[ "$pkg" =~ ^[a-z0-9][a-z0-9+.-]+$ ]]; then
            PAQUETES_RAW+=("$pkg")
        else
            [ -n "$pkg" ] && echo "⚠️ Nombre de paquete inválido omitido: $pkg" >> "$WARN_LOG"
        fi
    done < "$PKGS_MANUAL_FILE"
else
    echo "❌ Error: $PKGS_MANUAL_FILE no encontrado."
    exit 1
fi

# Inyección de paquetes CRÍTICOS (Declarativo)
PAQUETES_CRITICOS=(
    mate-menu 
    mate-desktop-environment-extras 
    mate-applets 
    bash-completion 
    sudo 
    zlib1g 
    libeudev1 
    libc6 
    libgcc-s1 
    vlc 
    vlc-plugin-base
)
PAQUETES_RAW+=("${PAQUETES_CRITICOS[@]}")

# Eliminar duplicados iniciales
PAQUETES_UNIQ=($(printf "%s\n" "${PAQUETES_RAW[@]}" | sort -u))
echo "   🔍 Resolviendo dependencias para ${#PAQUETES_UNIQ[@]} paquetes base (Sandbox)..."

# Resolución de dependencias recursiva usando el sandbox
DEPS_ALL=$(apt-cache -c "$APT_SANDBOX/apt.conf" depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances "${PAQUETES_UNIQ[@]}" 2>/dev/null | grep "^\w" | sort -u || true)

if [ -n "$DEPS_ALL" ]; then
    PAQUETES=($DEPS_ALL)
else
    PAQUETES=("${PAQUETES_UNIQ[@]}")
fi

echo "   ✅ Total de paquetes (base + dependencias) a procesar: ${#PAQUETES[@]}"

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
    local DEB_PATH=$(grep -m1 "/${pkg}_" "$POOL1_INDEX" || true)
    
    if [ -n "$DEB_PATH" ] && [ -f "$DEB_PATH" ]; then
        cp "$DEB_PATH" "$ISO_HOME/pool/local/" || echo "❌ Error copiando $pkg desde Pool1" >> "$WARN_LOG"
    else
        # 3. Buscar en Cache persistente
        local CACHED_DEB=$(ls "$PKG_CACHE/${pkg}_"*.deb 2>/dev/null | head -n1 || true)
        if [ -n "$CACHED_DEB" ] && [ -f "$CACHED_DEB" ]; then
            cp "$CACHED_DEB" "$ISO_HOME/pool/local/" || echo "❌ Error copiando $pkg desde Cache" >> "$WARN_LOG"
        else
            # 4. Descarga con Sandbox APT y Re-intento
            while [ "$count" -le "$retries" ]; do
                # Descargar a cache primero con flags de ultra-compatibilidad
                if (cd "$PKG_CACHE" && apt-get -c "$APT_SANDBOX/apt.conf" download "$pkg" -o APT::Get::AllowUnauthenticated=true -o Acquire::AllowInsecureRepositories=true -qq 2>/dev/null); then
                    local NEW_DEB=$(ls "$PKG_CACHE/${pkg}_"*.deb 2>/dev/null | head -n1 || true)
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
