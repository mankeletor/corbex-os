#!/bin/bash
# =========================================================
# postinst_final.sh - Post-instalación (v3.0)
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
# 4. Deshabilitar servicios innecesarios (✅ OpenRC)
# ─────────────────────────────────────────────
#if command -v rc-update >/dev/null; then
#    for s in bluetooth cups; do
#        rc-update del $s default 2>/dev/null || true
#    done
#fi

# ─────────────────────────────────────────────
# 5. Escritorio MATE - dconf global (✅ chroot)
# ─────────────────────────────────────────────
log "Configurando MATE/dconf..."
mkdir -p /etc/dconf/profile /etc/dconf/db/local.d

cat > /etc/dconf/profile/user << 'EOF'
user-db:user
system-db:local
EOF

if [ -f /root/corbex.dconf ]; then
    cp /root/corbex.dconf /etc/dconf/db/local.d/01-corbex-custom
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
# 10. Deshabilitar GNOME Keyring / MATE Keyring (✅ chroot)
#     Evita el diálogo "Set password for default keyring"
#     en entornos de autologin sin contraseña de sesión.
#     Estrategia en dos capas:
#       a) Override global via XDG autostart (afecta a todos los usuarios)
#       b) Keyring vacío pre-creado para el usuario alumno
# ─────────────────────────────────────────────
log "Deshabilitando GNOME/MATE keyring..."

# a) Deshabilitar autostart global de gnome-keyring
#    Cubre los tres componentes que pueden disparar el diálogo
AUTOSTART_DIR="/etc/xdg/autostart"
for component in gnome-keyring-secrets gnome-keyring-ssh gnome-keyring-pkcs11; do
    DESKTOP_FILE="${AUTOSTART_DIR}/${component}.desktop"
    if [ -f "$DESKTOP_FILE" ]; then
        # Agregar Hidden=true si no existe ya
        if ! grep -q "^Hidden=true" "$DESKTOP_FILE"; then
            echo "Hidden=true" >> "$DESKTOP_FILE"
            log "  ↳ $component deshabilitado vía Hidden=true"
        fi
    fi
done

# b) Pre-crear keyring vacío y sin contraseña para el usuario alumno
#    Esto evita el diálogo incluso si gnome-keyring arranca por otra vía
#    (ej: aplicación que llama a libsecret directamente)
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

log "Keyring deshabilitado ✅"

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
# 11b. Fix working directory en sesión X (autologin)
#      Sin esto el CWD al iniciar sesión es / en vez de $HOME
# ─────────────────────────────────────────────
log "Configurando fix working directory Xsession..."
mkdir -p /etc/X11/Xsession.d
cat > /etc/X11/Xsession.d/99cd-home << 'XSESSION_EOF'
# CorbexOS: fix CWD=/ en sesiones de autologin
if [ "$PWD" = "/" ] && [ -n "$HOME" ] && [ -d "$HOME" ]; then
    cd "$HOME"
fi
XSESSION_EOF

# ─────────────────────────────────────────────
# 12. Instalar PSeInt offline desde ISO
# ─────────────────────────────────────────────
log "Instalando PSeInt offline..."
if [ -s /root/extras/pseint.tgz ]; then
    tar xf /root/extras/pseint.tgz -C /opt/
    if [ -d /opt/pseint ]; then
        strip /opt/pseint/wxPSeInt /opt/pseint/pseint 2>/dev/null || true
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
# 12b. Instalar Avidemux offline desde bundle Flatpak
# ─────────────────────────────────────────────
log "Instalando Avidemux (Flatpak bundle offline)..."
AVIDEMUX_BUNDLE="/root/extras/avidemux.flatpak"
if [ -s "$AVIDEMUX_BUNDLE" ]; then
    # Asegurar que flatpak esté disponible
    if command -v flatpak >/dev/null; then
        # Instalar bundle offline sin red
        flatpak install --system --assumeyes --noninteractive \
            "$AVIDEMUX_BUNDLE" 2>&1 | tee -a "$LOG" || \
            log "⚠️ Error instalando Avidemux bundle"

        # Verificar instalación
        if flatpak list | grep -q "avidemux"; then
            log "Avidemux instalado vía Flatpak ✅"
        else
            log "⚠️ Avidemux no aparece en flatpak list tras instalación"
        fi
    else
        log "⚠️ flatpak no disponible en chroot, omitiendo Avidemux"
    fi
else
    log "⚠️ /root/extras/avidemux.flatpak no encontrado"
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
    
    # Limpiar extras copiados para ahorrar espacio
    rm -rf /root/extras || true
else
    log "⚠️ Antigravity no encontrado en /root/extras/"
fi

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
# corbex-firstrun.sh - Tareas de primer arranque
# Se ejecuta una sola vez como servicio OpenRC y se
# auto-deshabilita al finalizar.
# No requiere red - solo limpieza final y post-config.
# =========================================================
set -x
FLOG="/var/log/corbex-firstrun.log"
echo "$(date '+%Y-%m-%d %H:%M:%S') - FIRSTRUN INICIADO" > "$FLOG"

flog() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$FLOG"; }

# --- Limpieza final (seguro con sistema arrancado) ---
flog "Limpieza final..."
apt-get autoremove --purge -y 2>>"$FLOG" || true

apt-get clean

# --- Actualizar Fecha y Hora ---
flog "Sincronizando reloj por NTP..."
if command -v ntpsec-ntpdate >/dev/null; then
    ntpsec-ntpdate -u pool.ntp.org || flog "⚠️ Falló sincronización de hora"
    hwclock --systohc || true
else
    flog "⚠️ ntpdate no instalado"
fi

# --- Auto-deshabilitarse ---
flog "Deshabilitando servicio firstrun..."
rc-update del corbex-firstrun default 2>/dev/null || true

flog "FIRSTRUN FINALIZADO OK"
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