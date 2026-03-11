#!/bin/bash
# main.sh - Orquestador CorbexOS ISO Customizer
# Licencia: GNU GPL v3
# Filosofía: KISS / Modular
set -euo pipefail

VERSION="1.0rc1"
export BASE_DIR="$(pwd)"

# 0. Manejo de Argumentos
CLEAN_ARG=""
for arg in "$@"; do
    if [ "$arg" == "--clean" ]; then
        CLEAN_ARG="--clean"
        break
    fi
done

# 1. Cargar Configuración
if [ ! -f ./config.env ]; then
    echo "❌ Error: config.env no encontrado."
    exit 1
fi
set -a
source ./config.env
set +a

# Asegurar directorio de logs
mkdir -p "$WORKDIR/logs"

# --- REFACTOR DEL BLOQUE DE VALIDACIÓN EN main.sh ---

# 1. Validar solo la semilla (Entrada obligatoria)
if [ ! -f "$PKGS_MANUAL_FILE" ]; then
    echo "❌ Error: No existe la semilla de paquetes: $PKGS_MANUAL_FILE"
    echo "💡 Crealo con la lista de paquetes básicos que querés en la ISO."
    exit 1
fi

# 2. El archivo offline NO se valida aquí porque lo genera el Módulo 04
echo "✔ Semilla de paquetes detectada. El Cerebro generará la lista offline en el módulo 04."

echo "🚀 Iniciando proceso de customización $VERSION"
echo "================================================"

# 2. Ejecutar Módulos Secuencialmente
EXEC_START=$(date +%s)

# Función para ejecutar módulos con chequeo de error
run_module() {
    local mod_name="$1"
    shift
    local mod_file="./modules/$mod_name"
    if [ -x "$mod_file" ]; then
        bash "$mod_file" "$@" || { echo "❌ Error fatal en $mod_name"; exit 1; }
    else
        echo "❌ Error: $mod_file no existe o no es ejecutable."
        exit 1
    fi
}

# Preparar entorno (solo este script necesita permisos o acciones previas)
chmod +x modules/*.sh

run_module "01_check_deps.sh"
run_module "02_extract_iso.sh"

# Orden de Dependencia Crítico: 04 antes que 03 (Sincrónico)
run_module "04_repo_local.sh" "$CLEAN_ARG"
run_module "03_build_initrd.sh"

run_module "05_build_iso.sh"

# 3. Finalización
EXEC_END=$(date +%s)
DURATION=$((EXEC_END - EXEC_START))

# Conversión a h:mm:ss
HOURS=$((DURATION / 3600))
MINS=$(( (DURATION % 3600) / 60 ))
SECS=$(( DURATION % 60 ))

echo "================================================"
printf "🎉 ¡PROCESO COMPLETADO EN %02d:%02d:%02d!\n" $HOURS $MINS $SECS
echo "📀 ISO lista en: $WORKDIR"
echo "================================================"
