#!/bin/bash
# modules/04_repo_local.sh

echo "📦 [Módulo 04] Creando repositorio local (Pool1 + VSCode)..."

# Cargar configuración
[ -z "$ISO_HOME" ] && source ./config.env

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

# Añadir obligatorios para asegurar el funcionamiento de MATE
for critical in mate-menu mate-desktop-environment-extras mate-applets multiload-ng bash-completion sudo; do
    if [[ ! " ${PAQUETES[@]} " =~ " $critical " ]]; then
        PAQUETES+=("$critical")
    fi
done

# Directorios del repositorio
mkdir -p "$ISO_HOME/pool/main"
mkdir -p "$ISO_HOME/dists/excalibur/main/binary-amd64"
mkdir -p "$ISO_HOME/dists/excalibur/main/debian-installer/binary-amd64"

# 1. Extraer paquetes desde pool1.iso usando xorriso
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

echo "   Moviendo paquetes al repositorio local de la ISO..."
for pkg in "${PAQUETES[@]}"; do
    DEB=$(find "$EXTRACT_DIR" -name "${pkg}_*.deb" | head -1)
    if [ -n "$DEB" ]; then
        cp "$DEB" "$ISO_HOME/pool/main/" 2>/dev/null
    else
        # Si no esta en pool1, intentamos descargarlo (requiere internet en la maquina host)
        echo "   → $pkg no encontrado en Pool1, intentando descargar via apt-get download..."
        (cd "$ISO_HOME/pool/main/" && apt-get download "$pkg" -qq 2>/dev/null) || echo "   ❌ Error: $pkg no se pudo obtener"
    fi
done

# 3. Generar Índices de Apt con apt-ftparchive (Modelo Boris/Cisterna)
echo "   Generando índices de Apt robustos con apt-ftparchive..."
cd "$ISO_HOME"
# Crear el archivo Packages (sin comprimir) primero
apt-ftparchive packages pool/main > dists/excalibur/main/binary-amd64/Packages
# Generar la versión comprimida
gzip -c dists/excalibur/main/binary-amd64/Packages > dists/excalibur/main/binary-amd64/Packages.gz

# También para el instalador (udebs si los hubiera, o vacío por compatibilidad)
touch dists/excalibur/main/debian-installer/binary-amd64/Packages
gzip -c dists/excalibur/main/debian-installer/binary-amd64/Packages > dists/excalibur/main/debian-installer/binary-amd64/Packages.gz

# Limpiar temporales
rm -rf "$EXTRACT_DIR"
cd "$WORKDIR"

echo "✅ Repositorio local Apt configurado"
