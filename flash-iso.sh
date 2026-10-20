#!/usr/bin/env bash
# flash-iso.sh - Graba una imagen ISO a un pendrive USB de forma segura con pv y dd
# Autor: el Gentleman / CorbexOS team

set -euo pipefail

# Colores para la interfaz
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 1. Asegurar privilegios de root
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}ℹ️  Se requieren permisos de superusuario para interactuar con dispositivos de bloque.${NC}"
    echo -e "${CYAN}Reejecutando con sudo...${NC}"
    exec sudo "$0" "$@"
fi

# 2. Verificar dependencias necesarias
for cmd in pv dd lsblk findmnt stat; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED}❌ Error: No se encontró la herramienta '$cmd'. Por favor instalala antes de continuar.${NC}"
        exit 1
    fi
done

# 3. Selección o detección de la imagen ISO
ISO_PATH="${1:-}"

if [ -n "$ISO_PATH" ]; then
    if [ ! -f "$ISO_PATH" ]; then
        echo -e "${RED}❌ El archivo indicado no existe: $ISO_PATH${NC}"
        exit 1
    fi
else
    # Buscar ISOs en directorios comunes del proyecto
    mapfile -t ISO_CANDIDATES < <(find custom_corbex . -maxdepth 2 -type f -name "*.iso" 2>/dev/null | sort -r)

    if [ ${#ISO_CANDIDATES[@]} -eq 0 ]; then
        echo -e "${YELLOW}No se encontraron imágenes .iso automáticamente.${NC}"
        read -r -p "Ingresá la ruta completa a la ISO: " ISO_PATH
        if [ ! -f "$ISO_PATH" ]; then
            echo -e "${RED}❌ Archivo inválido o inexistente.${NC}"
            exit 1
        fi
    elif [ ${#ISO_CANDIDATES[@]} -eq 1 ]; then
        ISO_PATH="${ISO_CANDIDATES[0]}"
        echo -e "${GREEN}✔ ISO detectada automáticamente:${NC} ${BOLD}$ISO_PATH${NC}"
    else
        echo -e "\n${BOLD}${CYAN}Seleccioná la imagen ISO a grabar:${NC}"
        for i in "${!ISO_CANDIDATES[@]}"; do
            SIZE_HR=$(ls -lh "${ISO_CANDIDATES[$i]}" | awk '{print $5}')
            echo -e "  [${BOLD}$((i+1))${NC}] ${ISO_CANDIDATES[$i]} (${SIZE_HR})"
        done
        echo -e "  [${BOLD}0${NC}] Ingresar otra ruta manualmente"
        
        while true; do
            read -r -p "Opción [1-${#ISO_CANDIDATES[@]}]: " opt
            if [[ "$opt" =~ ^[1-9][0-9]*$ ]] && [ "$opt" -le "${#ISO_CANDIDATES[@]}" ]; then
                ISO_PATH="${ISO_CANDIDATES[$((opt-1))]}"
                break
            elif [ "$opt" = "0" ]; then
                read -r -p "Ruta a la ISO: " ISO_PATH
                if [ -f "$ISO_PATH" ]; then
                    break
                else
                    echo -e "${RED}Archivo inexistente. Probá de nuevo.${NC}"
                fi
            else
                echo -e "${RED}Opción inválida.${NC}"
            fi
        done
    fi
fi

ISO_SIZE=$(stat -c%s "$ISO_PATH")
ISO_SIZE_HR=$(ls -lh "$ISO_PATH" | awk '{print $5}')
echo -e "${CYAN}Imagen:${NC} $ISO_PATH (${ISO_SIZE_HR})"

# 4. Listar y seleccionar pendrive (dispositivos de almacenamiento)
seleccionar_dispositivo() {
    while true; do
        clear
        echo -e "${BOLD}${CYAN}======================================================${NC}"
        echo -e "${BOLD}${CYAN}       GRABADOR DE IMÁGENES ISO - CorbexOS           ${NC}"
        echo -e "${BOLD}${CYAN}======================================================${NC}\n"
        echo -e "ISO a grabar: ${GREEN}${ISO_PATH}${NC} (${ISO_SIZE_HR})\n"

        # Identificar dispositivos donde residen /, /boot, /home y swap para protegerlos
        SYSTEM_DISKS=$(lsblk -n -l -o PKNAME,MOUNTPOINTS | awk '$2 ~ /^\/($|boot|home)|\[SWAP\]/ {print $1}' | sort -u)

        # Buscar discos de tipo USB o removibles
        mapfile -t USB_DEVS < <(lsblk -d -p -n -l -o NAME,TRAN,RM,TYPE | awk '$4=="disk" && ($2=="usb" || $3=="1") {print $1}')

        if [ ${#USB_DEVS[@]} -eq 0 ]; then
            echo -e "${YELLOW}⚠️  No se detectaron pendrives o unidades USB conectadas.${NC}"
            echo -e "Conectá el pendrive a un puerto USB y seleccioná una opción:\n"
            echo -e "  [${BOLD}r${NC}] Re-escanear dispositivos"
            echo -e "  [${BOLD}a${NC}] Mostrar todos los discos (modo avanzado / no recomendado)"
            echo -e "  [${BOLD}q${NC}] Cancelar y salir\n"
            read -r -p "Acción: " accion
            case "$accion" in
                r|R) continue ;;
                a|A)
                    # Tomar todos los discos excepto los del sistema
                    mapfile -t USB_DEVS < <(lsblk -d -p -n -l -o NAME,TYPE | awk '$2=="disk" {print $1}')
                    ;;
                *) echo -e "${CYAN}Operación cancelada por el usuario.${NC}"; exit 0 ;;
            esac
        fi

        echo -e "${BOLD}Dispositivos disponibles:${NC}"
        echo -e "------------------------------------------------------"
        
        VALID_DEVS=()
        idx=1
        for dev in "${USB_DEVS[@]}"; do
            DEV_BASE=$(basename "$dev")
            DEV_SIZE=$(lsblk -d -n -o SIZE "$dev")
            DEV_MODEL=$(lsblk -d -n -o MODEL "$dev" | sed 's/^[ \t]*//;s/[ \t]*$//')
            DEV_TRAN=$(lsblk -d -n -o TRAN "$dev")
            
            # Chequear si contiene particiones críticas del sistema
            IS_SYSTEM=false
            for sys_d in $SYSTEM_DISKS; do
                if [ "$DEV_BASE" = "$sys_d" ]; then
                    IS_SYSTEM=true
                    break
                fi
            done

            if [ "$IS_SYSTEM" = true ]; then
                echo -e "  [${RED}BLOQUEADO${NC}] $dev ($DEV_SIZE - $DEV_MODEL) ${RED}<- CONTIENE EL SISTEMA OPERATIVO${NC}"
            else
                VALID_DEVS+=("$dev")
                echo -e "  [${BOLD}${idx}${NC}] ${GREEN}${dev}${NC} ($DEV_SIZE) - Modelo: ${DEV_MODEL:-Genérico} [Bus: ${DEV_TRAN:-desconocido}]"
                # Mostrar particiones y puntos de montaje si existen
                lsblk -n -l -o NAME,SIZE,FSTYPE,MOUNTPOINT "$dev" | awk 'NR>1 {printf "       └─ %s (%s, %s) %s\n", $1, $2, $3, $4}'
                ((idx++))
            fi
        done
        echo -e "------------------------------------------------------"
        echo -e "  [${BOLD}r${NC}] Re-escanear puertos"
        echo -e "  [${BOLD}q${NC}] Cancelar\n"

        if [ ${#VALID_DEVS[@]} -eq 0 ]; then
            echo -e "${RED}No hay dispositivos seguros disponibles para seleccionar.${NC}"
            read -r -p "Presioná Enter para reintentar o 'q' para salir: " re
            [[ "$re" =~ ^[qQ]$ ]] && exit 0
            continue
        fi

        read -r -p "Elegí el número del dispositivo destino [1-${#VALID_DEVS[@]}]: " choice
        case "$choice" in
            r|R) continue ;;
            q|Q) echo -e "${CYAN}Operación cancelada.${NC}"; exit 0 ;;
            *)
                if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [ "$choice" -le "${#VALID_DEVS[@]}" ]; then
                    TARGET_DEV="${VALID_DEVS[$((choice-1))]}"
                    break
                else
                    echo -e "${RED}Opción no válida.${NC}"
                    sleep 1
                fi
                ;;
        esac
    done
}

seleccionar_dispositivo

# 5. Confirmación destructiva con datos detallados
DEV_INFO=$(lsblk -d -n -o NAME,SIZE,MODEL,TRAN "$TARGET_DEV")
echo -e "\n${BOLD}${RED}⚠️  ¡ATENCIÓN! ESTA OPERACIÓN BORRARÁ TODO EL CONTENIDO DEL DISPOSITIVO DESTINO:${NC}"
echo -e "  Dispositivo: ${BOLD}${RED}${TARGET_DEV}${NC} (${DEV_INFO})"
echo -e "  Imagen ISO:  ${BOLD}${GREEN}${ISO_PATH}${NC} (${ISO_SIZE_HR})"
echo -e ""
read -r -p "¿Estás completamente seguro de continuar? Escribí 'SI' (en mayúsculas) para confirmar: " confirmacion

if [ "$confirmacion" != "SI" ]; then
    echo -e "${YELLOW}Grabación abortada por seguridad. No se modificó ningún disco.${NC}"
    exit 0
fi

# 6. Desmontar todas las particiones del dispositivo seleccionado
echo -e "\n${CYAN}Desmontando particiones en ${TARGET_DEV}...${NC}"

# Buscar todas las particiones montadas bajo el dispositivo (con ruta completa -p)
mapfile -t MOUNTED_PARTS < <(lsblk -n -l -p -o NAME,MOUNTPOINT "$TARGET_DEV" | awk '$2!="" {print $1}')

if [ ${#MOUNTED_PARTS[@]} -gt 0 ]; then
    for part in "${MOUNTED_PARTS[@]}"; do
        echo -e "  Desmontando $part..."
        umount "$part" 2>/dev/null || umount -f "$part" || {
            echo -e "${RED}No se pudo desmontar $part. Verificá si algún proceso está accediendo al directorio.${NC}"
            exit 1
        }
    done
    echo -e "${GREEN}✔ Todas las particiones fueron desmontadas correctamente.${NC}"
else
    echo -e "  No había particiones montadas en este dispositivo."
fi

# 7. Grabación con pv y dd
echo -e "\n${BOLD}${GREEN}Iniciando copia de la imagen...${NC}"
echo -e "${YELLOW}Por favor no desconectes el pendrive ni apagues la máquina.${NC}\n"

# Explicación del pipeline:
# pv lee la ISO, mide la tasa de transferencia, calcula tiempo restante con -s (size),
# y se lo envía a dd con bloque de 4MB y conv=fsync para vaciado de buffer seguro.
pv -tpreb -s "$ISO_SIZE" "$ISO_PATH" | dd of="$TARGET_DEV" bs=4M conv=fsync status=none

echo -e "\n${CYAN}Sincronizando buffers de disco (sync)...${NC}"
sync

echo -e "\n${BOLD}${GREEN}======================================================${NC}"
echo -e "${BOLD}${GREEN} ✔ ¡Grabación completada con éxito en ${TARGET_DEV}!     ${NC}"
echo -e "${BOLD}${GREEN}======================================================${NC}"
echo -e "Ya podés retirar el pendrive de forma segura y usarlo para bootear."
