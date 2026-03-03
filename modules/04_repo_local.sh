#!/bin/bash
# modules/04_repo_local.sh
# Lógica Complementaria Robusta v0.99rc25
set -euo pipefail
set -o pipefail

# Redirección de logs (Cerebro v0.99rc25)
LOG_FILE="$WORKDIR/logs/04_repo_local.log"
WARN_LOG="$WORKDIR/logs/warnings.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "📦 [Modulo 04] Creando repositorio local complementario..."

# Cargar configuración
if [ -z "${BASE_DIR:-}" ]; then
    BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
source "$BASE_DIR/config.env"

# Optimización de hilos (Max segura)
CPU_COUNT=$(nproc)
THREADS=$((CPU_COUNT + 1))
[ "$THREADS" -gt 8 ] && THREADS=8
echo "   Utilizando $THREADS hilos para procesamiento paralelo."

# 0. Cargar y Validar paquetes
echo "   Cargando y validando paquetes desde $PKGS_OFFLINE_FILE..."
PAQUETES_RAW=()
if [ -f "$PKGS_OFFLINE_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        [[ -z "$line" || "$line" =~ ^# || "$line" == Estado=* || "$line" == Err?=* || "$line" == Nombre ]] && continue
        pkg=$(echo "$line" | awk '{ if ($1 ~ /^[a-z][a-z]$/) print $2; else print $1; }' | sed 's/:.*//')
        
        # Validación Regex de nombre de paquete Debian
        if [[ "$pkg" =~ ^[a-z0-9][a-z0-9+.-]+$ ]]; then
            PAQUETES_RAW+=("$pkg")
        else
            [ -n "$pkg" ] && echo "⚠️ Nombre de paquete inválido omitido: $pkg" >> "$WARN_LOG"
        fi
    done < "$PKGS_OFFLINE_FILE"
else
    echo "❌ Error: $PKGS_OFFLINE_FILE no encontrado."
    exit 1
fi

# Inyección de paquetes CRÍTICOS (Declarativo)
PAQUETES_CRITICOS=(mate-menu mate-desktop-environment-extras mate-applets bash-completion sudo zlib1g libeudev1 libc6 libgcc-s1 vlc vlc-plugin-base)
PAQUETES_RAW+=("${PAQUETES_CRITICOS[@]}")

# Eliminar duplicados y ordenar
PAQUETES=($(printf "%s\n" "${PAQUETES_RAW[@]}" | sort -u))
echo "   ✅ Total de paquetes únicos a procesar: ${#PAQUETES[@]}"

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
export EXTRACT_DIR ISO_HOME BASE_PKGS_FILE POOL1_INDEX WARN_LOG
process_pkg() {
    local pkg=$1
    
    # 1. ¿Está en base?
    if grep -q "^${pkg}$" "$BASE_PKGS_FILE"; then return 0; fi

    # 2. Buscar en índice de Pool1 (Grep es más rápido que find)
    local DEB_PATH=$(grep -m1 "/${pkg}_" "$POOL1_INDEX" || true)
    
    if [ -n "$DEB_PATH" ] && [ -f "$DEB_PATH" ]; then
        cp "$DEB_PATH" "$ISO_HOME/pool/local/" || echo "❌ Error copiando $pkg" >> "$WARN_LOG"
    else
        # 3. Descarga
        (cd "$ISO_HOME/pool/local/" && apt-get download "$pkg" -qq 2>/dev/null) || echo "❌ No disponible: $pkg" >> "$WARN_LOG"
    fi
}
export -f process_pkg

echo "   Iniciando copia/descarga paralela..."
printf "%s\n" "${PAQUETES[@]}" | xargs -I {} -P "$THREADS" bash -c 'process_pkg "$@"' _ {}

# 4. Generar Índices Apt
echo "   Generando índices de repositorio local..."
cd "$ISO_HOME"
dpkg-scanpackages -m pool/local /dev/null | sed "s|^Filename: \(.*\)$|Filename: ./\1|g" | gzip -9c > dists/excalibur/local/binary-amd64/Packages.gz
zcat dists/excalibur/local/binary-amd64/Packages.gz > dists/excalibur/local/binary-amd64/Packages

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

rm -rf "$EXTRACT_DIR"
echo "✅ Módulo 04 finalizado exitosamente."
