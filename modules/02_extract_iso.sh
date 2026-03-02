#!/bin/bash
# modules/02_extract_iso.sh
set -euo pipefail

echo "💿 [Módulo 02] Extrayendo ISO original..."

# Cargar configuración if not loaded
# Carga de configuración corregida
if [ -z "$ISO_ORIGINAL" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../config.env"
fi

# Limpiar trabajo anterior
echo "   Limpiando $WORKDIR..."
rm -rf "$WORKDIR" 2>/dev/null
mkdir -p "$ISO_HOME"

# Extracción usando xorriso (no requiere sudo mount)
echo "   Extrayendo archivos de la ISO con xorriso..."
xorriso -osirrox on -indev "$ISO_ORIGINAL" -extract / "$ISO_HOME"

if [ $? -ne 0 ] || [ ! -d "$ISO_HOME/boot" ]; then
    echo "❌ Error fatal: La extracción de la ISO falló o está incompleta."
    exit 1
fi

echo "✅ ISO extraída correctamente en $ISO_HOME"
