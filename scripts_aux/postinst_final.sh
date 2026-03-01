#!/bin/bash
# postinst.sh - Optimizaciones finales para ESFP Córdoba
# Versión: PERSISTENTE (con /etc/skel y dconf robusto)

echo "=== Optimizando sistema para 4GB RAM (ESFP Córdoba) ==="

# Configuración de idioma y localización
echo "es_AR.UTF-8 UTF-8" > /etc/locale.gen
locale-gen es_AR.UTF-8
update-locale LANG=es_AR.UTF-8

# --------------------------
# FORZAR INSTALACIÓN DE PAQUETES (Cerebro + Cisterna)
# --------------------------
if [ -f /root/pkgs_manual.txt ]; then
    echo "📋 Procesando pkgs_manual.txt para asegurar instalación..."
    LISTA_PKGS=$(cat /root/pkgs_manual.txt | tr '\n' ' ')
    
    echo "⚙️ Ejecutando apt-get install para lista manual..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $LISTA_PKGS || echo "⚠️ Algunos paquetes fallaron, se reintentará en el primer arranque."
fi

# Reducir swappiness
echo "vm.swappiness=10" >> /etc/sysctl.conf

# Desactivar servicios innecesarios (Optimización RAM 4GB)
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
color-shading-type='vertical-gradient'
picture-filename='/usr/share/backgrounds/mate/nature/Aqua.jpg'
picture-options='zoom'
primary-color='rgb(88,145,188)'
secondary-color='rgb(60,143,37)'

[org/mate/power-manager]
sleep-display-ac=0
sleep-display-battery=0

[org/mate/sound]
allow-amplification=true
event-sounds=true

[org/mate/volume-control]
allow-amplification=true

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

[org/mate/desktop/peripherals/keyboard]
numlock-state='on'

# --------------------------------------------------
# CONFIGURACIÓN DEL PANEL (MATE Layout ESFP)
# --------------------------------------------------
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
DCONF

# ⚙️ Asegurar que dconf-cli está instalado ANTES de actualizar
if ! command -v dconf &>/dev/null; then
    echo "⚙️ Instalando dconf-cli para aplicar configuraciones..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y dconf-cli
fi

# Aplicar los cambios a la base de datos binaria global
if command -v dconf &>/dev/null; then
    echo "⚙️ Ejecutando dconf update (Global DB)..."
    dconf update || echo "⚠️ Falló dconf update"
    
    # También forzar compilación de esquemas si el comando existe
    if command -v glib-compile-schemas &>/dev/null; then
        glib-compile-schemas /usr/share/glib-2.0/schemas/
    fi
else
    echo "⚠️ Comando dconf no encontrado."
fi

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

# 2. Crear la configuración de LightDM (Autologin)
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-autologin.conf << EOF
[Seat:*]
autologin-user=alumno
autologin-user-timeout=0
autologin-session=mate
EOF
echo "✅ Autologin configurado para usuario alumno."

# --------------------------
# LIMPIEZA AGRESIVA FINAL
# --------------------------
echo "🗑️ Purgando terminales extra (xterm, uxterm)..."
DEBIAN_FRONTEND=noninteractive apt-get purge -y xterm uxterm || true

echo "🧹 Limpiando residuos de instalación y paquetes huérfanos..."
DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y || true
DEBIAN_FRONTEND=noninteractive apt-get clean -y || true

# Marcar la instalación
echo "INSTALACIÓN ESFP-CÓRDOBA - $(date)" >> /etc/issue
echo "✅ Sistema optimizado para ESFP Córdoba" >> /etc/motd

echo "=== Optimización completada ==="
exit 0
