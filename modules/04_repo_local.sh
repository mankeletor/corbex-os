#!/bin/bash
# modules/04_repo_local.sh

echo "📦 [Módulo 04] Creando repositorio local (Pool1 + VSCode)..."

# Cargar configuración
[ -z "$ISO_HOME" ] && source ./config.env

# 0. Cargar paquetes desde pkgs.txt
echo "   Cargando paquetes desde $PKGS_FILE..."
PAQUETES=()
if [ -f "$PKGS_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ -z "$line" || "$line" == Estado=* || "$line" == Err?=* || "$line" == Nombre ]]; then continue; fi
        pkg=$(echo "$line" | awk '{ if ($1 ~ /^[a-z][a-z]$/) print $2; else print $1; }' | sed 's/:.*//')
        [ -n "$pkg" ] && [[ ! "$pkg" =~ ^[./] ]] && PAQUETES+=("$pkg")
    done < "$PKGS_FILE"
else
    PAQUETES=(mate-desktop-environment-core mate-terminal network-manager)
fi

# Añadir obligatorios y corregir faltantes reportados
for critical in code mate-menu mate-desktop-environment-extras mate-applets multiload-ng bash-completion sudo; do
    if [[ ! " ${PAQUETES[@]} " =~ " $critical " ]]; then
        PAQUETES+=("$critical")
    fi
done

# Directorios del repositorio
mkdir -p "$ISO_HOME/pool/main" "$ISO_HOME/pool/main/c/code"
mkdir -p "$ISO_HOME/dists/excalibur/main/binary-amd64"
mkdir -p "$ISO_HOME/dists/excalibur/main/debian-installer/binary-amd64"

# 1. Extraer paquetes desde pool1.iso usando xorriso (evita sudo mount)
echo "   Extrayendo paquetes solicitados desde Pool1 (esto puede tardar)..."
EXTRACT_DIR="$WORKDIR/pool1_files"
mkdir -p "$EXTRACT_DIR"

# En lugar de extraer todo, buscamos los archivos en la ISO y los extraemos uno por uno
# O mejor, extraemos el árbol de pool/main que es manejable
xorriso -osirrox on -indev "$POOL1_ISO" -extract /pool/main "$EXTRACT_DIR"

# Copiar solo lo que está en PAQUETES o todo lo extraído para asegurar integridad
# Dado que queremos sistema MATE, copiaremos todo el main de pool1 si cabe, 
# o filtramos agresivamente. Copiemos lo necesario.
echo "   Filtrando y moviendo paquetes..."
for pkg in "${PAQUETES[@]}"; do
    [ "$pkg" = "code" ] && continue
    # Buscamos en el árbol extraído
    DEB=$(find "$EXTRACT_DIR" -name "${pkg}_*.deb" | head -1)
    if [ -n "$DEB" ]; then
        cp "$DEB" "$ISO_HOME/pool/main/" 2>/dev/null
    else
        echo "   ⚠️ $pkg no encontrado en Pool1"
    fi
done

# 2. Descargar VSCode
if [[ " ${PAQUETES[@]} " =~ " code " ]]; then
    echo "   → Descargando VSCode de Microsoft..."
    wget -q -O "$ISO_HOME/pool/main/c/code/code_vscode.deb" "$VSCODE_URL" || echo "   ⚠️ Error descargando VSCode"
fi

# 3. Generar Índices de Apt
echo "   Generando índices de Apt..."
cd "$ISO_HOME"
(cd pool && dpkg-scanpackages . /dev/null | gzip -9c > ../dists/excalibur/main/binary-amd64/Packages.gz)
touch dists/excalibur/main/debian-installer/binary-amd64/Packages.gz

# Limpiar temporales
rm -rf "$EXTRACT_DIR"
cd "$WORKDIR"

echo "✅ Repositorio local Apt configurado"
