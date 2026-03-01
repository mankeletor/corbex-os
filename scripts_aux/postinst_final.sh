#!/bin/bash
# postinst.sh - Optimizaciones finales para ESFP Córdoba
# Versión: PERSISTENTE (con /etc/skel y dconf robusto)

echo "=== Optimizando sistema para 4GB RAM (ESFP Córdoba) ==="

# Configuración de idioma y localización
echo "es_AR.UTF-8 UTF-8" > /etc/locale.gen
locale-gen es_AR.UTF-8
update-locale LANG=es_AR.UTF-8

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

# Configuraciones globales del sistema (todas las claves que NO son panel layout)
cat > /etc/dconf/db/local.d/01-esfp-custom << 'DCONF'
# ==================================================
# CONFIGURACIÓN MATE (Brisk Menu + ESFP Fix)
# ==================================================

[org/mate/marco/general]
compositing-manager=false
theme='Menta'
button-layout=':minimize,maximize,close'
allow-tiling=true

[org/mate/interface]
gtk-theme='Menta'
enable-animations=false
gtk-decoration-layout=':minimize,maximize,close'

[org/mate/desktop/background]
picture-filename='/usr/share/backgrounds/desktop-background'
picture-options='zoom'

[org/mate/power-manager]
sleep-display-ac=0
sleep-display-battery=0

[org/mate/sound]
allow-amplification=true
event-sounds=true

[org/mate/volume-control]
allow-amplification=true

[org/mate/terminal/profiles/default]
background-type='transparent'
background-darkness=0.85
use-theme-colors=false
visible-name='Default'

[org/mate/desktop/peripherals/keyboard]
numlock-state='on'
DCONF

# Aplicar los cambios a la base de datos de dconf
if command -v dconf &>/dev/null; then
    dconf update
    echo "✅ dconf sistema-db actualizado"
fi

# Forzar la recarga de esquemas
if command -v glib-compile-schemas &>/dev/null; then
    glib-compile-schemas /usr/share/glib-2.0/schemas/
fi

# --------------------------
# SCRIPT DE PRIMER LOGIN: aplica panel layout
# --------------------------
cat > /etc/profile.d/esfp-dconf-setup.sh << 'FIRSTLOGIN'
#!/bin/bash
# Aplica la configuración de panel MATE al usuario alumno en el primer login.

MARKER="/home/alumno/.config/esfp-dconf-applied"
[ -f "$MARKER" ] && return 0
[ "$USER" != "alumno" ] && return 0

# Esperar a que D-Bus esté disponible
for i in $(seq 1 20); do
    [ -n "$DBUS_SESSION_BUS_ADDRESS" ] && break
    sleep 0.5
done

# Inyectar configuración del panel vía dconf load
if command -v dconf &>/dev/null; then
dconf load / << 'SETTINGS'
[org/mate/panel/general]
object-id-list=['notification-area', 'clock', 'show-desktop', 'window-list', 'workspace-switcher', 'object-0', 'object-1']
toplevel-id-list=['top', 'bottom']

[org/mate/panel/objects/clock]
applet-iid='ClockAppletFactory::ClockApplet'
locked=true
object-type='applet'
position=0
relative-to-edge='end'
toplevel-id='top'

[org/mate/panel/objects/clock/prefs]
cities=['<location name="" city="Córdoba" timezone="America/Argentina/Cordoba" latitude="-31.316668" longitude="-64.216667" code="SACO" current="true"/>']
expand-locations=true
format='24-hour'

[org/mate/panel/objects/notification-area]
applet-iid='NotificationAreaAppletFactory::NotificationArea'
locked=true
object-type='applet'
position=10
relative-to-edge='end'
toplevel-id='top'

[org/mate/panel/objects/object-0]
applet-iid='MultiLoadAppletFactory::MultiLoadApplet'
object-type='applet'
position=196
relative-to-edge='end'
toplevel-id='top'

[org/mate/panel/objects/object-0/prefs]
view-cpuload=true
view-memload=true
view-netload=true

[org/mate/panel/objects/object-1]
applet-iid='BriskMenuFactory::BriskMenu'
object-type='applet'
position=0
toplevel-id='top'

[org/mate/panel/objects/show-desktop]
applet-iid='WnckletFactory::ShowDesktopApplet'
locked=true
object-type='applet'
position=0
toplevel-id='bottom'

[org/mate/panel/objects/window-list]
applet-iid='WnckletFactory::WindowListApplet'
locked=true
object-type='applet'
position=20
toplevel-id='bottom'

[org/mate/panel/objects/workspace-switcher]
applet-iid='WnckletFactory::WorkspaceSwitcherApplet'
locked=true
object-type='applet'
position=0
relative-to-edge='end'
toplevel-id='bottom'

[org/mate/panel/toplevels/bottom]
expand=true
orientation='bottom'
size=24

[org/mate/panel/toplevels/top]
expand=true
orientation='top'
size=24
SETTINGS

# Reiniciar el panel para aplicar el nuevo layout
mate-panel --replace &>/dev/null &

# Marcar como aplicado
mkdir -p /home/alumno/.config
touch "$MARKER"
chown alumno:alumno "$MARKER"
fi
FIRSTLOGIN

chmod 644 /etc/profile.d/esfp-dconf-setup.sh

# --------------------------
# CONFIGURAR SUDO Y AUTOLOGIN PARA ALUMNO
# --------------------------
if [ -d /etc/sudoers.d ]; then
    echo "alumno ALL=(ALL) ALL" > /etc/sudoers.d/alumno
    chmod 440 /etc/sudoers.d/alumno
fi

echo "⚙️ Configurando Autologin para el usuario alumno..."
# 1. Asegurar que el grupo existe y el usuario pertenece a él
groupadd -r autologin 2>/dev/null || true
usermod -aG autologin alumno

# 2. Crear la configuración de LightDM de forma limpia
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-autologin.conf << EOF
[Seat:*]
autologin-user=alumno
autologin-user-timeout=0
EOF
echo "✅ Autologin configurado."

# Marcar la instalación
echo "INSTALACIÓN ESFP-CÓRDOBA - $(date)" >> /etc/issue
echo "✅ Sistema optimizado para ESFP Córdoba" >> /etc/motd

echo "=== Optimización completada ==="
exit 0
