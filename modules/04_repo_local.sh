#!/bin/bash
# modules/04_repo_local.sh
# Lógica Híbrida V10: Extracción Xorriso + Indexación Monolith (dpkg-scanpackages)
set -euo pipefail

echo "📦 [Modulo 04] Creando repositorio local..."

# Cargar configuración
# Carga de configuración corregida
if [ -z "$ISO_ORIGINAL" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../config.env"
fi

# 0. Cargar paquetes desde pkgs_offline.txt (Cisterna)
echo "   Cargando paquetes para el repositorio offline desde $PKGS_OFFLINE_FILE..."
PAQUETES=()
if [ -f "$PKGS_OFFLINE_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ -z "$line" || "$line" == Estado=* || "$line" == Err?=* || "$line" == Nombre ]]; then continue; fi
        pkg=$(echo "$line" | awk '{ if ($1 ~ /^[a-z][a-z]$/) print $2; else print $1; }' | sed 's/:.*//')
        [ -n "$pkg" ] && [[ ! "$pkg" =~ ^[./] ]] && PAQUETES+=("$pkg")
    done < "$PKGS_OFFLINE_FILE"
else
    echo "❌ Error: $PKGS_OFFLINE_FILE no encontrado."
    exit 1
fi

# Añadir obligatorios y pre-dependencias criticas (V10)
for critical in mate-menu mate-desktop-environment-extras mate-applets bash-completion sudo zlib1g libeudev1 libc6 libgcc-s1 vlc vlc-plugin-base; do
    if [[ ! " ${PAQUETES[@]} " =~ " $critical " ]]; then
        PAQUETES+=("$critical")
    fi
done

# Directorios del repositorio complementario
mkdir -p "$ISO_HOME/pool/local"
mkdir -p "$ISO_HOME/dists/excalibur/local/binary-amd64"

# 1. Generar lista de paquetes BASE (Netinstall) para evitar duplicados
echo "   Identificando paquetes base de la ISO Netinstall..."
BASE_PKGS_FILE="$WORKDIR/base_packages.txt"
if [ -f "$ISO_HOME/dists/excalibur/main/binary-amd64/Packages" ]; then
    grep "^Package: " "$ISO_HOME/dists/excalibur/main/binary-amd64/Packages" | cut -d' ' -f2 | sort -u > "$BASE_PKGS_FILE"
    echo "   ✅ Detectados $(wc -l < "$BASE_PKGS_FILE") paquetes en el sistema base."
else
    touch "$BASE_PKGS_FILE"
    echo "   ⚠️ Advertencia: No se encontró índice de paquetes base."
fi

# 2. Extraer paquetes desde pool1.iso usando xorriso
echo "   Extrayendo paquetes solicitados desde Pool1..."
EXTRACT_DIR="$WORKDIR/pool1_files"
rm -rf "$EXTRACT_DIR" 2>/dev/null
mkdir -p "$EXTRACT_DIR"

xorriso -osirrox on -indev "$POOL1_ISO" -extract /pool "$EXTRACT_DIR" 2>/dev/null

DEB_COUNT=$(find "$EXTRACT_DIR" -name "*.deb" 2>/dev/null | wc -l)
if [ "$DEB_COUNT" -gt 0 ]; then
    echo "   ✅ Extracción de Pool1 exitosa ($DEB_COUNT paquetes)"
else
    echo "   ⚠️ Advertencia: No se encontraron paquetes en Pool1. Intentando descargar faltantes..."
fi

echo "   Procesando paquetes para POOL LOCAL (Multi-threading: $THREADS)..."
export EXTRACT_DIR ISO_HOME THREADS BASE_PKGS_FILE
process_pkg() {
    local pkg=$1
    
    # Prioridad 1: ¿Ya está en la base Netinstall?
    if grep -q "^${pkg}$" "$BASE_PKGS_FILE"; then
        return 0
    fi

    # Prioridad 2: Buscar en Pool1 (extraído)
    local DEB=$(find "$EXTRACT_DIR" -name "${pkg}_*.deb" | head -1)
    if [ -n "$DEB" ]; then
        cp "$DEB" "$ISO_HOME/pool/local/" 2>/dev/null
    else
        # Prioridad 3: Descarga (si hay red)
        (cd "$ISO_HOME/pool/local/" && apt-get download "$pkg" -qq 2>/dev/null) || echo "   ❌ No se pudo obtener: $pkg"
    fi
}
export -f process_pkg

printf "%s\n" "${PAQUETES[@]}" | xargs -I {} -P "$THREADS" bash -c 'process_pkg "$@"' _ {}

# 3. Generar Indices del Pool Local (v0.99rc24)
echo "   Generando indices para pool/local..."
cd "$ISO_HOME"

# Generar Packages para el pool LOCAL
if command -v pigz > /dev/null 2>&1; then
    dpkg-scanpackages -m pool/local /dev/null | sed "s|^Filename: \(.*\)$|Filename: ./\1|g" | pigz -p "$THREADS" -9c > dists/excalibur/local/binary-amd64/Packages.gz
else
    dpkg-scanpackages -m pool/local /dev/null | sed "s|^Filename: \(.*\)$|Filename: ./\1|g" | gzip -9c > dists/excalibur/local/binary-amd64/Packages.gz
fi

# Packages plano para compatibilidad
zcat dists/excalibur/local/binary-amd64/Packages.gz > dists/excalibur/local/binary-amd64/Packages

# Generar archivo Release para el componente LOCAL
echo "   Generando metadatos para el repositorio local..."
cat > apt-local-release.conf << EOF
APT::FTPArchive::Release::Origin "Devuan";
APT::FTPArchive::Release::Label "ESFP Cordoba Local Repo";
APT::FTPArchive::Release::Suite "excalibur";
APT::FTPArchive::Release::Codename "excalibur";
APT::FTPArchive::Release::Architectures "amd64";
APT::FTPArchive::Release::Components "local";
APT::FTPArchive::Release::Description "Paquetes Complementarios ESFP Cordoba";
EOF

apt-ftparchive -c apt-local-release.conf release dists/excalibur/local/binary-amd64/ > dists/excalibur/local/binary-amd64/Release
rm apt-local-release.conf

# Limpiar temporales
rm -rf "$EXTRACT_DIR"
cd "$WORKDIR"

echo "✅ Repositorio local Apt configurado en pool/local."
