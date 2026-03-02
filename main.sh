#!/bin/bash
# main.sh - Orquestador ESFP Córdoba ISO Customizer
# Licencia: GNU GPL v3
# Filosofía: KISS / Modular
set -euo pipefail

VERSION="0.99rc17"

# 1. Cargar Configuración
if [ ! -f ./config.env ]; then
    echo "❌ Error: config.env no encontrado."
    exit 1
fi
source ./config.env
set -a
source ./config.env
set +a

# Validar archivos de paquetes
for f in "$PKGS_OFFLINE_FILE" "$PKGS_MANUAL_FILE"; do
    if [ ! -f "$f" ]; then
        echo "❌ Error: Archivo crítico no encontrado: $f"
        exit 1
    fi
done

echo "🚀 Iniciando proceso de customización $VERSION"
echo "================================================"

# 2. Ejecutar Módulos Secuencialmente
EXEC_START=$(date +%s)

# Función para ejecutar módulos con chequeo de error
run_module() {
    local mod_file="./modules/$1"
    if [ -x "$mod_file" ]; then
        bash "$mod_file" || { echo "❌ Error fatal en $1"; exit 1; }
    else
        echo "❌ Error: $mod_file no existe o no es ejecutable."
        exit 1
    fi
}

# Preparar entorno (solo este script necesita permisos o acciones previas)
chmod +x modules/*.sh

run_module "01_check_deps.sh"
run_module "02_extract_iso.sh"

# Ejecución Paralela de Módulos 03 y 04 (V12.1)
# Se usa 'bash' explícitamente para asegurar que se ejecuten con bash,
# y se capturan los PIDs para esperar su finalización.
bash ./modules/03_build_initrd.sh &
PID03=$!
bash ./modules/04_repo_local.sh &
PID04=$!

# Inyectar configuración de Booteo (usando la plantilla)
echo "🎨 [Main] Aplicando plantilla de booteo (templates/isolinux.cfg)..."
cp ./templates/isolinux.cfg "$ISO_HOME/boot/isolinux/isolinux.cfg"
rm -f "$ISO_HOME/boot/isolinux/"{menu.cfg,stdmenu.cfg,vesamenu.c32} 2>/dev/null

echo "⏳ Esperando finalización de procesos paralelos (03_build_initrd.sh y 04_repo_local.sh)..."
wait $PID03 || { echo "❌ Error en Módulo 03 (03_build_initrd.sh)"; exit 1; }
wait $PID04 || { echo "❌ Error en Módulo 04 (04_repo_local.sh)"; exit 1; }

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
