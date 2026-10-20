#!/bin/bash
# test-iso.sh - Levanta la ISO de CorbexOS en QEMU
# Uso: ./test-iso.sh [ruta-a-la-iso]
#
# Ejemplos:
#   ./test-iso.sh custom_corbex/devuan-corbexos-20261011_2316.iso  # boot from CD (ISO)
#   ./test-iso.sh                                            # boot from HDD (installed)

set -euo pipefail

# Si no se da una ISO, indicar modo HDD e interrumpir si el disco no está presente
if [ $# -eq 0 ]; then
    echo "ℹ️ Modo HDD: probando la distro instalada en ../disco_virtual_netbook.qcow2"
    ISO_PATH=""
else
    ISO_PATH="$1"

    if [ ! -f "$ISO_PATH" ]; then
        echo "❌ ISO no encontrada: $ISO_PATH"
        exit 1
    fi
fi

# Directorio de trabajo donde quedará el NVRAM writable de OVMF
NVRAM_DIR="$(mktemp -d)"
trap 'rm -rf "$NVRAM_DIR"' EXIT

# Copia editable de las variables de OVMF (el original es de solo lectura)
cp /usr/share/OVMF/OVMF_VARS_4M.fd "$NVRAM_DIR/OVMF_VARS.fd"

# Log serial: captura kernel + instalador aunque la red o el video fallen.
# Útil para debug cuando no hay red (nc) ni splash legible.
SERIAL_LOG="${SERIAL_LOG:-$PWD/qemu-serial-$(date +%Y%m%d_%H%M%S).log}"
echo "📝 Log serial: $SERIAL_LOG"

QEMU_ARGS=(
    -enable-kvm -m 4G -cpu host -smp 8
    -hda ../disco_virtual_netbook.qcow2
    -vga virtio -display gtk
    -serial "file:$SERIAL_LOG"
    -device intel-hda -device hda-duplex,audiodev=snd0
    -device qemu-xhci,id=usb -device usb-tablet
    -audiodev pa,id=snd0
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd
    -drive if=pflash,format=raw,file="$NVRAM_DIR/OVMF_VARS.fd"
)

# Configurar arranque según modo
if [ -n "$ISO_PATH" ]; then
    echo "🔧 Modo CD: arrancando desde ISO"
    QEMU_ARGS+=(-cdrom "$ISO_PATH" -boot d -net nic -net user)
else
    echo "🔧 Modo HDD: arrancando desde disco instalado"
    QEMU_ARGS+=(-boot c)
fi

qemu-system-x86_64 "${QEMU_ARGS[@]}"
