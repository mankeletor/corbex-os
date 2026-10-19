#!/bin/bash
# 03_generate_sources.sh - Genera sources.list estático para la ISO
#
# Este módulo se ejecuta DESPUÉS de 04_repo_local.sh (con internet disponible)
# y ANTES de 03_build_initrd.sh. Su objetivo es generar un sources.list
# estático basado en el mejor mirror disponible en el momento del build,
# evitando que el sistema instalado tenga que hacer discovery HTTP en el
# primer arranque (lo cual puede fallar en escuelas sin internet).
#
# Salida: $ISO_HOME/corbex-sources.list (copiado luego por late_command a /etc/apt/sources.list)

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

# Redirección de logs
WORKDIR="${WORKDIR:-$BASE_DIR/custom_corbex}"
LOG_FILE="$WORKDIR/logs/03_generate_sources.log"
mkdir -p "$(dirname "$LOG_FILE")"
exec 3>>"$LOG_FILE"  # FD 3 para logs internos
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a >&3; }

log "=== Generando sources.list estático para la ISO ==="

# El script generador ya existe en el source tree
GENERATOR_SCRIPT="./modules/3.5_build_source.sh"

if [ ! -x "$GENERATOR_SCRIPT" ]; then
    log "Error: $GENERATOR_SCRIPT no existe o no es ejecutable"
    exit 1
fi

# Ejecutar el generador sin argumentos (modo automático: selecciona el mejor mirror)
log "Ejecutando discovery de mirror automático..."
SOURCE_LIST_OUTPUT="$("$GENERATOR_SCRIPT" 2>&1)" || {
    log "Error: falló la generación de sources.list:"
    log "$SOURCE_LIST_OUTPUT"
    exit 1
}

# Guardar el resultado en la ISO
OUTPUT_FILE="$ISO_HOME/corbex-sources.list"
echo "$SOURCE_LIST_OUTPUT" > "$OUTPUT_FILE"

# Verificar que se generó correctamente
if [ ! -s "$OUTPUT_FILE" ]; then
    log "Error: sources.list generado está vacío"
    exit 1
fi

# Contar líneas (debería ser al menos 3: excalibur, -updates, -security)
LINE_COUNT=$(echo "$SOURCE_LIST_OUTPUT" | grep -c "^deb " || echo 0)
log "Sources.list generado con $LINE_COUNT entradas:"
log "$SOURCE_LIST_OUTPUT"

log "Sources.list guardado en: $OUTPUT_FILE"
log "=== Módulo 03_generate_sources.sh completado ==="
exit 0