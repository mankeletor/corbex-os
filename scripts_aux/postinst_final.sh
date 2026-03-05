#!/bin/bash
LOG="/var/log/custom-postinst.log"
echo "$(date '+%Y-%m-%d %H:%M:%S') - postinst_final.sh INICIADO (PID $$  )" > "$LOG"
echo "Entorno: PATH=$PATH" >> "$LOG"
echo "Usuario: $(whoami), Dir: $(pwd)" >> "$LOG"
set -x  # verbose mode temporal para debug (muestra cada comando ejecutado)

echo "=== Optimizando sistema para netbooks ESFP Córdoba (4GB RAM) ==="

# 1. Idioma y locales
echo "es_AR.UTF-8 UTF-8" > /etc/locale.gen
locale-gen es_AR.UTF-8
update-locale LANG=es_AR.UTF-8

# 2. Instalación forzada de paquetes manuales (mejor debug)
if [ -f /root/pkgs_manual.txt ]; then
    echo "=== Procesando pkgs_manual.txt ==="
    LISTA_PKGS=$(cat /root/pkgs_manual.txt | tr '\n' ' ' | sed 's/  */ /g')
    
    echo "Actualizando fuentes APT..."
    apt-get update || { echo "ERROR: apt update falló - chequeá sources.list y repo local"; }

    echo "Instalando paquetes manuales..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends --fix-broken $LISTA_PKGS 2>&1 | tee /root/postinst_manual_pkgs.log
    echo "Instalación manual completada. Ver /root/postinst_manual_pkgs.log para detalles/errores."
else
    echo "No se encontró /root/pkgs_manual.txt - saltando instalación manual."
fi

# 3. Reducir swappiness para RAM baja
echo "vm.swappiness=10" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1 || true

# 4. Desactivar servicios innecesarios
SERVICIOS_INNECESARIOS="cups bluetooth whoopsie speech-dispatcher"
for servicio in $SERVICIOS_INNECESARIOS; do
    if [ -f /etc/init.d/$servicio ]; then
        update-rc.d $servicio disable 2>/dev/null || true
        echo "Servicio SysV $servicio desactivado"
    fi
done

if command -v rc-update >/dev/null; then
    for servicio in bluetooth cups; do
        rc-update del $servicio default 2>/dev/null || true
    done
    echo "Servicios OpenRC desactivados"
fi

# 5. Configuración global MATE via dconf (system-db)
mkdir -p /etc/dconf/profile /etc/dconf/db/local.d

# Perfil dconf (usuario + system local)
cat > /etc/dconf/profile/user << 'EOF'
user-db:user
system-db:local
EOF

# Aplicar configuraciones desde el template inyectado
if [ -f /root/esfp.dconf ]; then
    echo "Aplicando configuración dconf desde template..."
    # Asegurar que dconf-cli está disponible para la carga
    apt-get install -y --no-install-recommends dconf-cli dbus-x11 || true
    
    # Inyectar el archivo de configuración directamente en la base de datos local
    cp /root/esfp.dconf /etc/dconf/db/local.d/01-esfp-custom
    
    # Compilar esquemas y actualizar DB
    glib-compile-schemas /usr/share/glib-2.0/schemas/ || true
    dconf update || echo "Error actualizando base de datos dconf"
else
    echo "⚠️ Warning: /root/esfp.dconf no encontrado. Saltando dconf."
fi

# 5.1 Script de Primer Inicio (Firstrun)
# Se ejecuta al primer login del usuario alumno (vía /etc/profile.d)
cat > /etc/profile.d/esfp-firstrun.sh << 'EOF'
#!/bin/bash
# esfp-firstrun.sh - Tareas de limpieza y ajuste en el primer inicio
MARKER="$HOME/.config/esfp-firstrun-done"

# Solo ejecutar para el usuario alumno y una sola vez
if [ "$USER" = "alumno" ] && [ ! -f "$MARKER" ]; then
    echo "🚀 Iniciando tareas de primer inicio ESFP Córdoba..."
    
    # Asegurar que dconf tome el perfil global
    if command -v dconf >/dev/null; then
        dconf update
    fi
    
    # Marcar como completado
    mkdir -p "$(dirname "$MARKER")"
    touch "$MARKER"
    echo "✅ Tareas de primer inicio completadas."
fi
EOF
chmod 644 /etc/profile.d/esfp-firstrun.sh

# 6. Protección de paquetes de AUDIO (evita que el instalador los purgue)
echo "Protegiendo paquetes de audio..."
apt-mark manual pulseaudio pulseaudio-utils pipewire pipewire-bin pipewire-pulse wireplumber libcanberra-pulse 2>/dev/null || true

# 7. Sudo para alumno (sin password)
if [ -d /etc/sudoers.d ]; then
    echo "alumno ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/alumno
    chmod 440 /etc/sudoers.d/alumno
fi

# 7. Autologin LightDM (sin grupo extra)
echo "Configurando autologin para alumno..."
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-autologin.conf << EOF
[Seat:*]
autologin-user=alumno
autologin-user-timeout=0
autologin-session=mate
EOF

# 8. Nano como editor default (tu mejora robusta)
if command -v update-alternatives >/dev/null; then
    update-alternatives --set editor /bin/nano 2>/dev/null ||
    update-alternatives --set editor /usr/bin/nano 2>/dev/null || true
fi

# 9. Opcional: Asegurar rc.conf si no llegó desde initrd
if [ -f /rc.conf ]; then
    cp /rc.conf /etc/rc.conf
    echo "rc.conf copiado desde inyección"
fi

# 10. Limpieza agresiva
echo "Limpiando paquetes y residuos..."
apt-get purge -y xterm uxterm 2>/dev/null || true
apt-get autoremove --purge -y || true
apt-get autoclean -y
apt-get clean

# 11. Marca final
echo "$(date '+%Y-%m-%d %H:%M:%S') - postinst_final.sh FINALIZADO OK" >> "$LOG"
exit 0