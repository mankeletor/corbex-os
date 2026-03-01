#!/bin/bash
# modules/04_repo_local.sh

echo "📦 [Módulo 04] Creando repositorio local (Pool1 + VSCode)..."

# Cargar configuración
[ -z "$ISO_HOME" ] && source ./config.env

# Re-cargar paquetes (podríamos exportarlos desde main.sh pero mejor ser robustos)
PAQUETES=()
while IFS= read -r line || [ -n "$line" ]; do
    if [[ -z "$line" || "$line" == Estado=* || "$line" == Err?=* || "$line" == Nombre ]]; then continue; fi
    pkg=$(echo "$line" | awk '{ if ($1 ~ /^[a-z][a-z]$/) print $2; else print $1; }' | sed 's/:.*//')
    [ -n "$pkg" ] && [[ ! "$pkg" =~ ^[./] ]] && PAQUETES+=("$pkg")
done < "$PKGS_FILE"
for critical in code mate-menu mate-desktop-environment-extras mate-applets multiload-ng; do
    [[ ! " ${PAQUETES[@]} " =~ " $critical " ]] && PAQUETES+=("$critical")
done

# Montar POOL1
sudo mkdir -p /mnt/pool1
sudo mount -o loop "$POOL1_ISO" /mnt/pool1

# Estructura del repositorio
mkdir -p "$ISO_HOME/pool/main" "$ISO_HOME/pool/main/c/code"
mkdir -p "$ISO_HOME/dists/excalibur/main/"{binary-amd64,debian-installer/binary-amd64}

echo "   Copiando .deb de Pool1..."
for pkg in "${PAQUETES[@]}"; do
    [ "$pkg" = "code" ] && continue
    DEB=$(find /mnt/pool1/pool -name "${pkg}_*.deb" 2>/dev/null | head -1)
    [ -n "$DEB" ] && cp "$DEB" "$ISO_HOME/pool/main/" 2>/dev/null || true
done

# Descargar VSCode
if [[ " ${PAQUETES[@]} " =~ " code " ]]; then
    echo "   → Descargando VSCode de Microsoft..."
    wget -q -O "$ISO_HOME/pool/main/c/code/code_vscode.deb" "$VSCODE_URL" || echo "   ⚠️ Error descargando VSCode"
fi

# Generar Índices
echo "   Generando índices de Apt..."
cd "$ISO_HOME"
cd pool
dpkg-scanpackages . /dev/null | gzip -9c > ../dists/excalibur/main/binary-amd64/Packages.gz
cd ..
touch dists/excalibur/main/debian-installer/binary-amd64/Packages.gz

sudo umount /mnt/pool1
sudo rmdir /mnt/pool1
cd "$WORKDIR"

echo "✅ Repositorio local Apt configurado"
