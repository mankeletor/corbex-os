#!/bin/bash
# =========================================================
# postinst_final.sh - Post-instalación (v3.2)
# CorbexOS - Optimizado para Netbooks (4GB RAM)
#
# CONTEXTO: Se ejecuta vía in-target (chroot del target).
#   / = /target (sistema instalado)
#   /root = /target/root
#   NO hay red confiable, NO hay kernel corriendo.
#   Las tareas que requieren red o sistema arrancado van
#   al servicio OpenRC corbex-firstrun.
# =========================================================

LOG="/var/log/custom-postinst.log"
echo "$(date '+%Y-%m-%d %H:%M:%S') - postinst_final.sh INICIADO" > "$LOG"
set -x  # Modo debug

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG"; }

log "=== Optimizando sistema para CorbexOS ==="

# ─────────────────────────────────────────────
# 1. Idioma y locales (✅ seguro en chroot)
# ─────────────────────────────────────────────
log "Configurando idioma es_AR.UTF-8..."
echo "es_AR.UTF-8 UTF-8" > /etc/locale.gen
locale-gen es_AR.UTF-8
update-locale LANG=es_AR.UTF-8

# ─────────────────────────────────────────────
# 2. Paquetes manuales (✅ repos ya configurados)
# ─────────────────────────────────────────────
if [ -f /root/pkgs_install.txt ]; then
    LISTA_PKGS=$(tr '\n' ' ' < /root/pkgs_install.txt | sed 's/  */ /g')
    log "Instalando paquetes: $LISTA_PKGS"
    apt-get update || log "⚠️ Falló update local/mirror"
    # shellcheck disable=SC2086 # Word splitting intencional: lista de paquetes
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        --no-install-recommends --fix-broken \
        $LISTA_PKGS 2>&1 | tee /root/postinst_manual_pkgs.log
fi

# ─────────────────────────────────────────────
# 3. Swappiness (✅ solo escribir, se aplica al arrancar)
# ─────────────────────────────────────────────
log "Configurando swappiness=10..."
if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
    echo "vm.swappiness=10" >> /etc/sysctl.conf
fi


# ─────────────────────────────────────────────
# 5. Escritorio MATE - dconf global (✅ chroot)
# ─────────────────────────────────────────────
log "Configurando MATE/dconf..."
mkdir -p /etc/dconf/profile /etc/dconf/db/local.d /etc/dconf/db/locks

cat > /etc/dconf/profile/user << 'EOF'
user-db:user
system-db:local
EOF

if [ -f /root/corbex.dconf ]; then
    cp /root/corbex.dconf /etc/dconf/db/local.d/01-corbex-custom
    
    # BLOQUEAR las claves de terminal para que el usuario no las pueda cambiar
    # Esto fuerza el uso del perfil system-wide
    cat > /etc/dconf/db/locks/01-corbex-terminal << 'LOCKS'
    /org/mate/terminal/profiles/default/background-darkness
    /org/mate/terminal/profiles/default/background-type
    /org/mate/terminal/profiles/default/background-color
    /org/mate/terminal/profiles/default/foreground-color
    /org/mate/terminal/profiles/default/use-theme-colors
    /org/mate/terminal/profiles/default/working-directory
    /org/mate/terminal/profiles/default/default-show-menubar
LOCKS
    
    dconf update || log "⚠️ Error en dconf update"
fi

# ─────────────────────────────────────────────
# 6. Sudoers restringido (✅ chroot)
# ─────────────────────────────────────────────
log "Configurando sudo restringido..."
if [ -d /etc/sudoers.d ]; then
    cat > /etc/sudoers.d/alumno << 'EOF'
alumno ALL=(ALL) NOPASSWD: /usr/bin/apt, /usr/bin/apt-get, \
/usr/bin/apt-cache, /usr/bin/apt-mark, /usr/bin/dpkg, /sbin/reboot, \
/sbin/shutdown, /sbin/poweroff
EOF
    chmod 440 /etc/sudoers.d/alumno
fi

# ─────────────────────────────────────────────
# 7. Autologin LightDM (✅ chroot)
# ─────────────────────────────────────────────
log "Configurando autologin..."
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-autologin.conf << 'EOF'
[Seat:*]
autologin-user=alumno
autologin-user-timeout=0
autologin-session=mate
EOF

# ─────────────────────────────────────────────
# 8. Editor por defecto (✅ chroot)
# ─────────────────────────────────────────────
update-alternatives --set editor /bin/nano 2>/dev/null || true

# ─────────────────────────────────────────────
# 9. Verificar rc.conf (✅ chroot)
#    late_command ya copió /rc.conf a /target/etc/rc.conf
#    (dentro del chroot eso es /etc/rc.conf)
# ─────────────────────────────────────────────
if [ -f /etc/rc.conf ]; then
    log "rc.conf encontrado en /etc/rc.conf ✅"
else
    log "⚠️ rc.conf no encontrado en /etc/rc.conf"
fi

# ─────────────────────────────────────────────
# 10. Configurar GNOME Keyring para autologin (✅ chroot)
#
#     ESTRATEGIA (3 capas):
#       a) Solo deshabilitar gnome-keyring-secrets (el que pide contraseña).
#          Dejar ssh y pkcs11 activos → el daemon sigue disponible para
#          apps Electron como Antigravity y Chrome que usan libsecret.
#       b) Keyring vacío pre-creado para usuario alumno → desbloqueado
#          desde el primer arranque sin intervención del usuario.
#       c) NetworkManager configurado con backend "keyfile" → guarda
#          contraseñas WiFi en /etc/NetworkManager/system-connections/
#          en vez de intentar usar el keyring (evita pérdida de redes
#          guardadas en entornos de autologin).
# ─────────────────────────────────────────────
log "Configurando keyring para autologin + Antigravity + Chrome..."

# a) Deshabilitar SOLO el componente que dispara el diálogo de contraseña.
#    gnome-keyring-ssh y gnome-keyring-pkcs11 se dejan habilitados
#    para que el daemon quede disponible para libsecret (Antigravity, Chrome, etc.)
AUTOSTART_DIR="/etc/xdg/autostart"
SECRETS_DESKTOP="${AUTOSTART_DIR}/gnome-keyring-secrets.desktop"
if [ -f "$SECRETS_DESKTOP" ]; then
    if ! grep -q "^Hidden=true" "$SECRETS_DESKTOP"; then
        echo "Hidden=true" >> "$SECRETS_DESKTOP"
        log "  ↳ gnome-keyring-secrets deshabilitado (diálogo suprimido)"
    fi
else
    # Si no existe el .desktop, crearlo explícitamente para asegurar
    # que no se auto-genere en ninguna versión futura del paquete
    cat > "$SECRETS_DESKTOP" << 'DESKTOP_EOF'
[Desktop Entry]
Type=Application
Name=Certificate and Key Storage
Hidden=true
DESKTOP_EOF
    log "  ↳ gnome-keyring-secrets.desktop creado con Hidden=true"
fi
log "  ↳ gnome-keyring-ssh y gnome-keyring-pkcs11 activos (daemon disponible para libsecret)"

# b) Pre-crear keyring vacío y desbloqueado para el usuario alumno.
#    Formato gwkr (sin contraseña) — gnome-keyring lo acepta como desbloqueado
#    sin pedir contraseña al inicio de sesión.
KEYRING_DIR="/home/alumno/.local/share/keyrings"
mkdir -p "$KEYRING_DIR"

cat > "${KEYRING_DIR}/default.keyring" << 'KEYRING_EOF'
[keyring]
display-name=Default keyring
ctime=0
mtime=0
lock-on-idle=false
lock-after=false
KEYRING_EOF

echo "default.keyring" > "${KEYRING_DIR}/default"

chown -R alumno:alumno "$KEYRING_DIR"
chmod 700 "$KEYRING_DIR"
chmod 600 "${KEYRING_DIR}/default.keyring"
chmod 644 "${KEYRING_DIR}/default"
log "  ↳ Keyring vacío pre-creado para alumno (desbloqueado al iniciar sesión)"

# c) NetworkManager: backend keyfile para no depender del keyring en WiFi
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/10-corbex-keyfile.conf << 'NM_EOF'
# CorbexOS: guardar credenciales WiFi en archivo plano
# en vez de intentar usar gnome-keyring (que no tiene contraseña
# en sesiones de autologin y causaría pérdida de redes guardadas).
[main]
plugins=keyfile

[keyfile]
unmanaged-devices=none
NM_EOF
log "  ↳ NetworkManager configurado con backend keyfile"

log "Keyring configurado ✅"

# ─────────────────────────────────────────────
# 11. Limpieza parcial (✅ seguro en chroot)
#     apt-get autoremove va en firstrun
# ─────────────────────────────────────────────
log "Limpieza parcial..."
apt-get purge -y xterm 2>/dev/null || true
apt-get clean
rc-update add openntpd default
rc-service openntpd start || true


# ─────────────────────────────────────────────
# 11c. Fix PATH — agregar /usr/sbin y /sbin (✅ chroot)
#      En Devuan/Debian moderno sbin está fusionado en /usr/sbin
#      pero no siempre aparece en el PATH del usuario normal.
#      profile.d  → aplica a shells interactivos de login.
#      /etc/environment → aplica a cualquier sesión vía PAM
#                         (incluyendo autologin de LightDM).
# ─────────────────────────────────────────────
log "Configurando PATH con /usr/sbin y /sbin..."
cat > /etc/profile.d/corbex-path.sh << 'PATH_EOF'
# CorbexOS: asegurar /usr/sbin y /sbin en PATH para todos los usuarios
case ":$PATH:" in
    *:/usr/sbin:*) ;;
    *) export PATH="$PATH:/usr/sbin" ;;
esac
case ":$PATH:" in
    *:/sbin:*) ;;
    *) export PATH="$PATH:/sbin" ;;
esac
PATH_EOF
chmod 644 /etc/profile.d/corbex-path.sh

# Aplica también a sesiones X vía PAM (autologin LightDM)
if ! grep -q "/usr/sbin" /etc/environment 2>/dev/null; then
    echo 'PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games:/usr/sbin:/sbin' \
        >> /etc/environment
fi
log "PATH configurado ✅"

# ─────────────────────────────────────────────
# 11d. Fix directorio inicial del terminal MATE
#      MATE Terminal (y LightDM autologin) a veces
#      inician el shell con PWD=/ en vez de $HOME.
#      Solución: detectar en .bashrc si PWD=/ y
#      hacer cd $HOME automáticamente.
#      Esto es más confiable que dconf working-directory
#      porque funciona siempre, independiente de D-Bus.
# ─────────────────────────────────────────────
log "Configurando directorio inicial del terminal para alumno..."
ALUMNO_HOME="/home/alumno"
mkdir -p "$ALUMNO_HOME"

# Crear .bashrc base si no existe (copia de /etc/skel)
if [ ! -f "$ALUMNO_HOME/.bashrc" ] && [ -f /etc/skel/.bashrc ]; then
    cp /etc/skel/.bashrc "$ALUMNO_HOME/.bashrc"
fi

# Agregar el fix al final del .bashrc (idempotente)
if ! grep -q "corbex-homedir-fix" "$ALUMNO_HOME/.bashrc" 2>/dev/null; then
    cat >> "$ALUMNO_HOME/.bashrc" << 'BASHRC_FIX'

# CorbexOS: corbex-homedir-fix
# Si el terminal abre con PWD=/ (bug de autologin+MATE Terminal),
# ir al HOME automáticamente para no quedar en el directorio raíz.
if [ "$PWD" = "/" ]; then
    cd "$HOME" 2>/dev/null || true
fi
BASHRC_FIX
    log "  ↳ Fix de directorio inicial agregado a .bashrc de alumno ✅"
fi

# Asegurar que .bashrc pertenece al usuario alumno
chown alumno:alumno "$ALUMNO_HOME/.bashrc" 2>/dev/null || true
chmod 644 "$ALUMNO_HOME/.bashrc"
log "Directorio inicial del terminal configurado ✅"

# ─────────────────────────────────────────────
# 12. Instalar PSeInt offline desde ISO
# ─────────────────────────────────────────────
log "Instalando PSeInt offline..."
if [ -s /root/extras/pseint.tgz ]; then
    tar xf /root/extras/pseint.tgz -C /opt/
    if [ -d /opt/pseint ]; then
        strip --strip-unneeded /opt/pseint/wxPSeInt /opt/pseint/pseint 2>/dev/null || true
        cat > /usr/share/applications/pseint.desktop << DESKTOP
[Desktop Entry]
Name=PSeInt
Exec=/opt/pseint/wxPSeInt
Icon=/opt/pseint/imgs/icon64.png
Type=Application
Categories=Development;Education;
DESKTOP
        log "PSeInt instalado ✅"
    fi
else
    log "⚠️ /root/extras/pseint.tgz no encontrado"
fi

# ─────────────────────────────────────────────
# 12b. Instalar Avidemux desde AppImage
#      FUSE puede no estar disponible en el sistema base,
#      por eso se extrae el AppImage y se ejecuta el binario
#      directamente desde squashfs-root.
# ─────────────────────────────────────────────
log "Instalando Avidemux (AppImage extraído)..."
AVIDEMUX_APPIMAGE="/root/extras/avidemux_2.8.1.appImage"
DESKTOP_DIR=""
if [ -s "$AVIDEMUX_APPIMAGE" ]; then
    if [ -d /home/alumno/Desktop ]; then
        DESKTOP_DIR="/home/alumno/Desktop"
    fi
    if [ -d /home/alumno/Escritorio ]; then
        DESKTOP_DIR="/home/alumno/Escritorio"
    fi
    cp "$AVIDEMUX_APPIMAGE" "$DESKTOP_DIR/"
    chown alumno:alumno "$DESKTOP_DIR/avidemux_2.8.1.appImage"
    chmod +x "$DESKTOP_DIR/avidemux_2.8.1.appImage"

    log "Avidemux instalado ✅"
else
    log "⚠️ /root/extras/avidemux_2.8.1.appImage no encontrado"
fi

# ─────────────────────────────────────────────
# 12c. Instalar Google Chrome offline desde ISO
#      Al instalarse vía dpkg, Chrome agrega automáticamente su repo
#      en /etc/apt/sources.list.d/google-chrome.list → los alumnos
#      reciben actualizaciones automáticas con apt upgrade.
# ─────────────────────────────────────────────
log "Instalando Google Chrome offline..."
CHROME_DEB="/root/extras/google-chrome-stable.deb"
if [ -s "$CHROME_DEB" ]; then
    DEBIAN_FRONTEND=noninteractive dpkg -i "$CHROME_DEB" 2>/dev/null || \
        apt-get install -f -y 2>/dev/null || true
    if dpkg -l google-chrome-stable 2>/dev/null | grep -q "^ii"; then
        log "Google Chrome instalado ✅"
    else
        log "⚠️ Google Chrome no pudo instalarse correctamente"
    fi
else
    log "⚠️ /root/extras/google-chrome-stable.deb no encontrado"
fi

# ─────────────────────────────────────────────
# 13. Instalar Antigravity offline desde ISO
# ─────────────────────────────────────────────
log "Instalando Antigravity offline..."
AGDIR="/root/extras/antigravity"
if [ -s "$AGDIR/antigravity-repo-key.gpg" ] && \
   ls "$AGDIR"/antigravity_*.deb 1>/dev/null 2>&1; then
    mkdir -p /etc/apt/keyrings
    cp "$AGDIR/antigravity-repo-key.gpg" /etc/apt/keyrings/
    DEBIAN_FRONTEND=noninteractive dpkg -i "$AGDIR"/antigravity_*.deb 2>/dev/null || \
        apt-get install -f -y 2>/dev/null || true
    echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] \
https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ \
antigravity-debian main" > /etc/apt/sources.list.d/antigravity.list
    log "Antigravity instalado ✅"
else
    log "⚠️ Antigravity no encontrado en /root/extras/"
fi

# Limpiar directorio extras — al final de TODAS las instalaciones
# para no cortar el acceso a otros extras si una sección falla.
rm -rf /root/extras || true
log "Directorio extras limpiado ✅"

# ─────────────────────────────────────────────
# 14. Crear servicio FIRSTRUN (OpenRC)
#     Se ejecuta UNA vez en el primer arranque real
#     y se auto-deshabilita.
#     Ya no requiere red - solo limpieza y post-config.
# ─────────────────────────────────────────────
log "Instalando servicio corbex-firstrun..."

# 14a. Script principal del firstrun
mkdir -p /usr/local/sbin
cat > /usr/local/sbin/corbex-firstrun.sh << 'FIRSTRUN_SCRIPT'
#!/bin/bash
# =========================================================
# corbex-firstrun.sh - Tareas de primer arranque (v2.0)
# CorbexOS - Se ejecuta una sola vez como servicio OpenRC
# =========================================================
set -e  # Fail on error, pero con manejo en cada comando

FLOG="/var/log/corbex-firstrun.log"
exec > >(tee -a "$FLOG") 2>&1

flog() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

flog "=== CorbexOS Firstrun iniciado ==="
flog "Version: $(cat /etc/corbex-version 2>/dev/null || echo 'unknown')"
flog "Hardware: $(dmidecode -s system-product-name 2>/dev/null || echo 'unknown')"

# --- 1. Configurar terminal para usuario alumno ---
flog "Configurando perfil de MATE Terminal..."
if id alumno &>/dev/null; then
    # Esperar a que D-Bus de sistema esté listo
    sleep 2
    
    # Configurar dconf como alumno vía dbus-launch
    su - alumno -c 'export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id - u)/bus; dconf write /org/mate/terminal/profiles/default/background-darkness 0.85' 2>/dev/null || \
        flog "⚠️ No se pudo configurar background-darkness"
    
    su - alumno -c 'export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id - u)/bus; dconf write /org/mate/terminal/profiles/default/background-type "transparent"' 2>/dev/null || true
    
    su - alumno -c 'export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id - u)/bus; dconf write /org/mate/terminal/profiles/default/working-directory "/home/alumno"' 2>/dev/null || true
    
    su - alumno -c 'export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id - u)/bus; dconf write /org/mate/terminal/profiles/default/default-show-menubar true' 2>/dev/null || true
    
    flog "Terminal configurada ✅"
else
    flog "⚠️ Usuario alumno no existe"
fi

# --- 1.5 Esperar red y Generar sources.list dinámico ---
flog "Esperando conexión a Internet (max 60s)..."
NET_OK=false
for i in {1..12}; do
    if ping -q -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 || curl -s -I --connect-timeout 3 http://dev1mir.registrationsplus.net >/dev/null 2>&1; then
        NET_OK=true
        break
    fi
    sleep 5
done

if [ "$NET_OK" = "true" ]; then
    flog "Red detectada. Generando /etc/apt/sources.list dinámico..."
    if [ -x "/usr/local/sbin/corbex-build-sources.sh" ]; then
        if /usr/local/sbin/corbex-build-sources.sh "dev1mir.registrationsplus.net" > /tmp/sources.list.new 2>>"$FLOG"; then
            mv /tmp/sources.list.new /etc/apt/sources.list
            flog "sources.list generado exitosamente ✅"
            apt-get update -qq 2>/dev/null || flog "⚠️ apt-get update falló luego de generar sources.list"
        else
            flog "⚠️ Falló la generación. Se reintentará en el próximo arranque."
            exit 1
        fi
    else
        flog "⚠️ Script corbex-build-sources.sh no encontrado o no ejecutable. Ignorando."
    fi
else
    flog "⚠️ Sin conexión a internet tras 60s. Aplazando firstrun para el próximo reinicio..."
    exit 1
fi

# --- 2. Limpieza de paquetes (con timeout) ---
flog "Limpieza de paquetes..."
export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

# Configurar timeout corto para apt
cat > /etc/apt/apt.conf.d/99corbex-firstrun << 'APTCONF'
Acquire::Timeout "30";
Acquire::Retries "1";
APT::Get::Assume-Yes "true";
APTCONF

apt-get autoremove --purge -y 2>/dev/null || flog "⚠️ autoremove falló (posible sin red)"
apt-get clean
rm -f /etc/apt/apt.conf.d/99corbex-firstrun

# --- 3. Sincronización de hora (background, no bloqueante) ---
#     El paquete en Devuan Excalibur se llama 'ntpsec-ntpdate'
#     (reemplaza al obsoleto 'ntpdate') e instala el binario
#     /usr/sbin/ntpdate como drop-in replacement.
#     Fallback: sntp (de ntpsec) o chronyc si está disponible.
(
    flog "Sincronizando hora vía NTP..."
    if command -v ntpdate >/dev/null 2>&1; then
        timeout 15 ntpdate -u pool.ntp.org 2>/dev/null \
            && hwclock --systohc 2>/dev/null \
            && flog "Hora sincronizada con ntpdate ✅" \
            || flog "⚠️ ntpdate falló o timeout"
    elif command -v sntp >/dev/null 2>&1; then
        timeout 15 sntp -s pool.ntp.org 2>/dev/null \
            && hwclock --systohc 2>/dev/null \
            && flog "Hora sincronizada con sntp ✅" \
            || flog "⚠️ sntp falló o timeout"
    elif command -v chronyc >/dev/null 2>&1; then
        chronyc makestep 2>/dev/null \
            && flog "Hora sincronizada con chronyc ✅" \
            || flog "⚠️ chronyc falló"
    else
        flog "⚠️ No hay cliente NTP disponible (ntpdate/sntp/chronyc)"
    fi
) &

# --- 4. Auto-deshabilitar servicio ---
flog "Deshabilitando firstrun..."
rc-update del corbex-firstrun default 2>/dev/null || true

flog "=== Firstrun completado ==="
exit 0
FIRSTRUN_SCRIPT
chmod +x /usr/local/sbin/corbex-firstrun.sh

# 14b. Init script OpenRC
cat > /etc/init.d/corbex-firstrun << 'INITSCRIPT'
#!/sbin/openrc-run

description="CorbexOS - Configuración de primer arranque"

depend() {
    want NetworkManager
    after NetworkManager bootmisc
    keyword -shutdown -reboot
}

start() {
    ebegin "Ejecutando configuración de primer arranque CorbexOS..."
    /usr/local/sbin/corbex-firstrun.sh
    eend $?
}
INITSCRIPT
chmod +x /etc/init.d/corbex-firstrun
rc-update add NetworkManager default 2>/dev/null || true
rc-update add corbex-firstrun default 2>/dev/null || true

# ─────────────────────────────────────────────
log "postinst_final.sh FINALIZADO OK"
echo "$(date '+%Y-%m-%d %H:%M:%S') - FINALIZADO OK" >> "$LOG"
exit 0