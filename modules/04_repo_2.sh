#!/usr/bin/env bash
# modules/04_repo_local.sh
# Genera repositorio local offline + relleno opcional de paquetes faltantes
# Versión integrada con el flujo principal del proyecto ESFP Córdoba

set -euo pipefail

# ────────────────────────────────────────────────
# Cargar configuración del proyecto
# ────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$BASE_DIR/config.env"

# Variables del proyecto (definidas en config.env)
: "${WORKDIR:?Error: WORKDIR no definido en config.env}"
: "${ISO_HOME:?Error: ISO_HOME no definido en config.env}"
: "${POOL1_ISO:?Error: POOL1_ISO no definido en config.env}"
: "${BASE_DIR:?}"

# Configuración específica del módulo
POOL_LOCAL="${ISO_HOME}/pool/local"
DIST_DIR="${ISO_HOME}/dists/excalibur/local"
BINARY_DIR="${DIST_DIR}/binary-amd64"
ARCH="amd64"
SUITE="excalibur"
COMPONENT="local"

LISTA_MANUAL="${BASE_DIR}/pkgs_manual.txt"

# Activar relleno dinámico (descarga online si falta paquete)
FILL_MISSING="${FILL_MISSING:-true}"
FILL_MIRROR="${FILL_MIRROR:-http://deb.devuan.nz/devuan}"

# ────────────────────────────────────────────────
# Funciones auxiliares
# ────────────────────────────────────────────────
log() { echo "[04_repo_local] $*" >&2; }
error() { echo "[04_repo_local] ERROR: $*" >&2; exit 1; }
ensure_dir() { mkdir -p "$1" || error "No se pudo crear $1"; }

check_commands() {
    for cmd in dpkg-scanpackages gzip apt-cache apt-get find md5sum; do
        if ! command -v "$cmd" >/dev/null; then
            error "Falta herramienta requerida: $cmd"
        fi
    done
}

# ────────────────────────────────────────────────
# Inicialización
# ────────────────────────────────────────────────
log "Iniciando construcción del repositorio local..."
ensure_dir "$POOL_LOCAL"
ensure_dir "$BINARY_DIR"

if [ ! -s "$LISTA_MANUAL" ]; then
    error "pkgs_manual.txt vacío o no existe en $LISTA_MANUAL"
fi
check_commands

# ────────────────────────────────────────────────
# Paso 1: Preparar lista de paquetes manuales
# ────────────────────────────────────────────────
cp "$LISTA_MANUAL" "${WORKDIR}/pkgs_manual_clean.txt"
log "Paquetes manuales deseados: $(wc -l < "${WORKDIR}/pkgs_manual_clean.txt")"

# ────────────────────────────────────────────────
# Paso 2: Generar lista completa (manuales + dependencias)
# ────────────────────────────────────────────────
log "Calculando dependencias de los paquetes manuales..."

APT_CONFIG_DIR="${WORKDIR}/apt-temp"
ensure_dir "$APT_CONFIG_DIR"
ensure_dir "${APT_CONFIG_DIR}/lists/partial"
cat > "${APT_CONFIG_DIR}/sources.list" << EOF
deb $FILL_MIRROR $SUITE main contrib non-free non-free-firmware
EOF

> "${WORKDIR}/pkgs_full.txt"
> "${WORKDIR}/pkgs_deps.txt"

while IFS= read -r pkg; do
    echo "$pkg" >> "${WORKDIR}/pkgs_full.txt"
    apt-cache -c "${APT_CONFIG_DIR}/apt.conf" depends "$pkg" 2>/dev/null | \
        grep '^  Depende: ' | awk '{print $2}' >> "${WORKDIR}/pkgs_deps.txt" || true
done < "${WORKDIR}/pkgs_manual_clean.txt"

if [ -s "${WORKDIR}/pkgs_deps.txt" ]; then
    cat "${WORKDIR}/pkgs_deps.txt" >> "${WORKDIR}/pkgs_full.txt"
fi
sort -u "${WORKDIR}/pkgs_full.txt" > "${WORKDIR}/pkgs_to_include.txt"
rm -f "${WORKDIR}/pkgs_deps.txt"

log "Lista completa (manuales + deps): $(wc -l < "${WORKDIR}/pkgs_to_include.txt") paquetes"

# ────────────────────────────────────────────────
# Paso 3: Extraer Pool1.iso
# ────────────────────────────────────────────────
EXTRACT_DIR="${WORKDIR}/pool1_extract"
log "Extrayendo Pool1.iso a $EXTRACT_DIR..."
rm -rf "$EXTRACT_DIR" 2>/dev/null
ensure_dir "$EXTRACT_DIR"

if [ ! -f "$POOL1_ISO" ]; then
    error "Archivo POOL1_ISO no encontrado en: $POOL1_ISO"
fi

xorriso -osirrox on -indev "$POOL1_ISO" -extract /pool "$EXTRACT_DIR" 2>/dev/null || {
    error "Falló la extracción de $POOL1_ISO"
}

POOL1_INDEX="${WORKDIR}/pool1_index.txt"
find "$EXTRACT_DIR" -type f -name "*.deb" > "$POOL1_INDEX"
log "Pool1 indexado con $(wc -l < "$POOL1_INDEX") paquetes."

# ────────────────────────────────────────────────
# Paso 4: Copiar paquetes disponibles desde Pool1
# ────────────────────────────────────────────────
log "Copiando paquetes disponibles desde Pool1..."
copiados_local=0
while IFS= read -r pkg; do
    deb_path=$(grep -m1 "/${pkg}_" "$POOL1_INDEX" || true)
    if [ -n "$deb_path" ] && [ -f "$deb_path" ]; then
        if cp -v "$deb_path" "${POOL_LOCAL}/" 2>>"${WORKDIR}/warnings.log"; then
            ((copiados_local++))
        fi
    fi
done < "${WORKDIR}/pkgs_to_include.txt"
log "Copiados desde Pool1: $copiados_local"

# ────────────────────────────────────────────────
# Paso 5: Relleno online (opcional)
# ────────────────────────────────────────────────
copiados_online=0
if [ "$FILL_MISSING" = "true" ]; then
    log "Rellenando paquetes faltantes desde mirror online..."
    DOWNLOAD_DIR="${WORKDIR}/downloads_temp"
    ensure_dir "$DOWNLOAD_DIR"

    while IFS= read -r pkg; do
        if ! ls "${POOL_LOCAL}/${pkg}_"*.deb &>/dev/null; then
            log "Descargando $pkg..."
            if apt-get download \
                -c "${APT_CONFIG_DIR}/apt.conf" \
                -o Dir::Cache::archives="$DOWNLOAD_DIR" \
                "$pkg" 2>>"${WORKDIR}/warnings.log"; then
                mv "$DOWNLOAD_DIR"/*.deb "${POOL_LOCAL}/" 2>/dev/null && ((copiados_online++))
            fi
        fi
    done < "${WORKDIR}/pkgs_to_include.txt"
    rm -rf "$DOWNLOAD_DIR"
    log "Relleno completado: $copiados_online paquetes nuevos descargados"
fi

# ────────────────────────────────────────────────
# Paso 6: Generar índices del repositorio
# ────────────────────────────────────────────────
log "Generando índices del repositorio local..."

cd "$ISO_HOME"

# Packages.gz
dpkg-scanpackages -m pool/local /dev/null | \
    sed "s|^Filename: \(.*\)$|Filename: ./\1|g" | \
    gzip -9c > "dists/excalibur/local/binary-amd64/Packages.gz"

# Packages plano (sin comprimir)
zcat "dists/excalibur/local/binary-amd64/Packages.gz" > "dists/excalibur/local/binary-amd64/Packages"

# Archivo Release COMPLETO con MD5Sum (como en tu script original)
log "Generando Release con checksums MD5..."
cat > "dists/excalibur/local/binary-amd64/Release" << EOF
Origin: Devuan ESFP Córdoba
Label: ESFP Córdoba Local Repo
Suite: ${SUITE}
Codename: ${SUITE}
Date: $(date -Ru)
Architectures: ${ARCH}
Components: ${COMPONENT}
Description: Paquetes offline para instalación sin internet

MD5Sum:
$(cd "${ISO_HOME}" && find "dists/excalibur/local" -type f -name "Packages*" -print0 | sort -z | xargs -0 md5sum | sed 's/^\([0-9a-f]\{32\}\)  /  \1  /')
EOF

# ────────────────────────────────────────────────
# Verificación y limpieza
# ────────────────────────────────────────────────
cd "$BASE_DIR"

if [ ! -s "${BINARY_DIR}/Packages.gz" ]; then
    error "Packages.gz vacío o no generado"
fi

total_paquetes=$(zcat "${BINARY_DIR}/Packages.gz" | grep -c '^Package:')
rm -rf "$EXTRACT_DIR" "$POOL1_INDEX" "$APT_CONFIG_DIR" 2>/dev/null

log "✅ Repositorio local generado correctamente"
log "   Paquetes totales disponibles: $total_paquetes"
log "   Copiados desde Pool1: $copiados_local"
log "   Descargados online: $copiados_online"

exit 0