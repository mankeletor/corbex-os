#!/bin/bash
# postinst.sh - Optimizaciones finales para ESFP Córdoba
# Versión: PERSISTENTE (con /etc/skel y dconf robusto)

echo "=== Optimizando sistema para 4GB RAM (ESFP Córdoba) ==="

# Configuración de idioma y localización
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

# Reducir swappiness
echo "vm.swappiness=10" >> /etc/sysctl.conf

# Desactivar servicios innecesarios
SERVICIOS_INNECESARIOS="cups bluetooth whoopsie avahi-daemon speech-dispatcher ModemManager"
for servicio in $SERVICIOS_INNECESARIOS; do
    if [ -f /etc/init.d/$servicio ]; then
        update-rc.d $servicio disable
        echo "Servicio $servicio desactivado"
    fi
done

# OpenRC: desactivar servicios
if command -v rc-update &> /dev/null; then
    rc-update del bluetooth default 2>/dev/null || true
    rc-update del cups default 2>/dev/null || true
    rc-update del avahi-daemon default 2>/dev/null || true
    rc-update del ModemManager default 2>/dev/null || true
    echo "Servicios OpenRC desactivados"
fi

# Limpiar basura
apt-get autoclean -y

# --------------------------
# CONFIGURACIÓN DE MATE (SISTEMA-DB)
# Aplica valores por defecto para TODOS los usuarios.
# --------------------------
mkdir -p /etc/dconf/profile
mkdir -p /etc/dconf/db/local.d

# Perfil: el usuario usa su db + la db del sistema
cat > /etc/dconf/profile/user << 'PROFILE'
user-db:user
system-db:local
PROFILE

# Aplicar configuraciones desde el template inyectado
if [ -f /root/esfp.dconf ]; then
    echo "Aplicando configuración dconf (system-db) desde template..."
    # Asegurar que dconf-cli está disponible
    apt-get install -y --no-install-recommends dconf-cli dbus-x11 || true
    
    # Inyectar el archivo de configuración directamente en la base de datos local
    cp /root/esfp.dconf /etc/dconf/db/local.d/01-esfp-custom
    
    # Aplicar los cambios a la base de datos de dconf
    if command -v dconf &>/dev/null; then
        dconf update
        echo "✅ dconf sistema-db actualizado"
    fi

    # Forzar la recarga de esquemas
    if command -v glib-compile-schemas &>/dev/null; then
        glib-compile-schemas /usr/share/glib-2.0/schemas/
    fi
else
    echo "⚠️ Warning: /root/esfp.dconf no encontrado."
fi

# Protección de paquetes de AUDIO (evita que el instalador los purgue)
echo "Protegiendo paquetes de audio..."
apt-mark manual pulseaudio pulseaudio-utils pipewire pipewire-bin pipewire-pulse wireplumber libcanberra-pulse 2>/dev/null || true

# --------------------------
# SCRIPT DE PRIMER LOGIN: esfp-firstrun.sh
# --------------------------
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

# --------------------------
# CONFIGURAR SUDO PARA ALUMNO
# --------------------------
if [ -d /etc/sudoers.d ]; then
    echo "alumno ALL=(ALL) ALL" > /etc/sudoers.d/alumno
    chmod 440 /etc/sudoers.d/alumno
fi

# 7. Autologin LightDM
echo "Configurando autologin para alumno..."
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-autologin.conf << EOF
[Seat:*]
autologin-user=alumno
autologin-user-timeout=0
autologin-session=mate
EOF

# 8. Nano como editor default
if command -v update-alternatives >/dev/null; then
    update-alternatives --set editor /bin/nano 2>/dev/null ||
    update-alternatives --set editor /usr/bin/nano 2>/dev/null || true
fi

# 9. Limpieza agresiva de paquetes y residuos
echo "Limpiando paquetes y residuos..."
apt-get purge -y xterm 2>/dev/null || true
apt-get autoremove --purge -y || true
apt-get autoclean -y
apt-get clean

# Marcar la instalación
echo "INSTALACIÓN ESFP-CÓRDOBA - $(date)" >> /etc/issue
echo "✅ Sistema optimizado para ESFP Córdoba" >> /etc/motd

echo "=== Optimización completada ==="
exit 0
