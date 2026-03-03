#!/bin/bash
# postinst_final.sh - Optimizaciones finales para ESFP Córdoba
# Versión: PERSISTENTE (con /etc/skel y dconf robusto) - Corregida 03-mar-2026

set -e  # Salir si hay error grave

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
SERVICIOS_INNECESARIOS="cups bluetooth whoopsie avahi-daemon speech-dispatcher ModemManager"
for servicio in $SERVICIOS_INNECESARIOS; do
    if [ -f /etc/init.d/$servicio ]; then
        update-rc.d $servicio disable 2>/dev/null || true
        echo "Servicio SysV $servicio desactivado"
    fi
done

if command -v rc-update >/dev/null; then
    for servicio in bluetooth cups avahi-daemon ModemManager; do
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

# Configuraciones detalladas (tu template actualizado)
cat > /etc/dconf/db/local.d/01-esfp-custom << 'EOF'
# [Tu bloque DCONF completo aquí - lo copié tal cual de tu versión actual]
[org/gnome/desktop/interface]
color-scheme='default'

[org/gtk/settings/file-chooser]
date-format='regular'
location-mode='path-bar'
show-hidden=false
show-size-column=true
show-type-column=true
sidebar-width=169
sort-column='name'
sort-directories-first=true
sort-order='ascending'
type-format='category'
window-position=(178, 179)
window-size=(1081, 574)

[org/mate/caja/window-state]
geometry='800x550+0+25'
maximized=false
start-with-sidebar=true
start-with-status-bar=true
start-with-toolbar=true

[org/mate/desktop/accessibility/keyboard]
bouncekeys-beep-reject=true
bouncekeys-delay=300
bouncekeys-enable=false
enable=false
feature-state-change-beep=false
mousekeys-accel-time=1200
mousekeys-enable=false
mousekeys-init-delay=160
mousekeys-max-speed=750
slowkeys-beep-accept=true
slowkeys-beep-press=true
slowkeys-beep-reject=false
slowkeys-delay=300
slowkeys-enable=false
stickykeys-enable=false
stickykeys-latch-to-lock=true
stickykeys-modifier-beep=true
stickykeys-two-key-off=true
timeout=120
timeout-enable=false
togglekeys-enable=false

[org/mate/desktop/background]
color-shading-type='vertical-gradient'
picture-filename='/usr/share/backgrounds/mate/nature/Aqua.jpg'
picture-options='zoom'
primary-color='rgb(88,145,188)'
secondary-color='rgb(60,143,37)'

[org/mate/desktop/peripherals/keyboard]
numlock-state='off'

[org/mate/desktop/session]
session-start=1772520957

[org/mate/desktop/sound]
event-sounds=true
theme-name='freedesktop'

[org/mate/eom/ui]
image-collection=false

[org/mate/marco/general]
num-workspaces=2
theme='Menta'

[org/mate/mate-menu/plugins/applications]
last-active-tab=1

[org/mate/panel/general]
object-id-list=['notification-area', 'clock', 'show-desktop', 'window-list', 'workspace-switcher', 'object-1', 'object-0']
toplevel-id-list=['top', 'bottom']

[org/mate/panel/objects/clock]
applet-iid='ClockAppletFactory::ClockApplet'
locked=true
object-type='applet'
position=0
relative-to-edge='end'
toplevel-id='top'

[org/mate/panel/objects/clock/prefs]
custom-format=''
format='24-hour'

[org/mate/panel/objects/notification-area]
applet-iid='NotificationAreaAppletFactory::NotificationArea'
locked=true
object-type='applet'
position=10
relative-to-edge='end'
toplevel-id='top'

[org/mate/panel/objects/object-0]
applet-iid='MateMenuAppletFactory::MateMenuApplet'
object-type='applet'
position=0
toplevel-id='top'

[org/mate/panel/objects/object-1]
applet-iid='MultiLoadAppletFactory::MultiLoadApplet'
object-type='applet'
position=147
relative-to-edge='end'
toplevel-id='top'

[org/mate/panel/objects/object-1/prefs]
view-memload=true
view-netload=true

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
screen=0
size=24
y=826
y-bottom=0

[org/mate/panel/toplevels/top]
expand=true
orientation='top'
screen=0
size=24

[org/mate/sound]
allow-amplification=true

[org/mate/system-monitor]
current-tab=3
maximized=false
window-state=(935, 528, 50, 50)

[org/mate/system-monitor/disktreenew]
col-7-width=300

[org/mate/system-monitor/proctree]
col-26-width=133

[org/mate/terminal/profiles/default]
allow-bold=false
background-color='#000000000000'
background-darkness=0.84724689165186506
background-type='transparent'
bold-color='#000000000000'
foreground-color='#AAAAAAAAAAAA'
palette='#2E2E34343636:#CCCC00000000:#4E4E9A9A0606:#C4C4A0A00000:#34346565A4A4:#757550507B7B:#060698209A9A:#D3D3D7D7CFCF:#555557575353:#EFEF29292929:#8A8AE2E23434:#FCFCE9E94F4F:#72729F9FCFCF:#ADAD7F7FA8A8:#3434E2E2E2E2:#EEEEEEEEECEC'
use-theme-colors=false
visible-name='Default'

[org/mate/volume-control]
allow-amplification=true
EOF

# Asegurar dependencias dconf
apt-get install -y --no-install-recommends dconf-cli dbus-x11 || true

# Aplicar dconf global
if command -v dconf >/dev/null; then
    echo "Aplicando dconf global..."
    dbus-run-session -- dconf update || echo "dconf update falló (posible dbus issue)"
    glib-compile-schemas /usr/share/glib-2.0/schemas/ || true
else
    echo "dconf no encontrado - instalá dconf-cli manual si persiste."
fi

# Volcado a /etc/skel para persistencia en nuevos usuarios
mkdir -p /etc/skel/.config/dconf
dconf dump / > /etc/skel/.config/dconf/user 2>/dev/null || true
chmod 644 /etc/skel/.config/dconf/user 2>/dev/null || true
echo "Config dconf volcada a /etc/skel para nuevos usuarios."

# 6. Sudo para alumno (sin password, pero cuidado en prod)
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
echo "INSTALACIÓN ESFP-CÓRDOBA OPTIMIZADA - $(date)" >> /etc/issue
echo "Sistema preparado para aulas ESFP Córdoba" >> /etc/motd

echo "=== Optimización FINAL completada! ==="
exit 0