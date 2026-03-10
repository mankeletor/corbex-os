#!/bin/bash
# =========================================================
# postinst_final.sh - Post-instalación (v2.0)
# Corbex OS - Optimizado para Netbooks (4GB RAM)
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

log "=== Optimizando sistema para Corbex OS ==="

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
if [ -f /root/pkgs_manual.txt ]; then
    LISTA_PKGS=$(tr '\n' ' ' < /root/pkgs_manual.txt | sed 's/  */ /g')
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
if command -v rc-update >/dev/null; then
    for s in bluetooth cups; do
        rc-update del $s default 2>/dev/null || true
    done
fi

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
alumno ALL=(ALL) NOPASSWD: /usr/bin/apt, /usr/bin/apt-get, /usr/bin/apt-cache, /usr/bin/apt-mark, /usr/bin/dpkg
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
# 10. Configurar usuario alumno (✅ chroot)
# ─────────────────────────────────────────────
log "Configurando usuario alumno..."
chsh -s /bin/bash alumno
usermod -d /home/alumno -m alumno 2>/dev/null || true

# ─────────────────────────────────────────────
# 11. Limpieza parcial (✅ seguro en chroot)
#     apt-get autoremove va en firstrun
# ─────────────────────────────────────────────
log "Limpieza parcial..."
apt-get purge -y xterm 2>/dev/null || true
apt-get clean

# ─────────────────────────────────────────────
# 12. Crear servicio FIRSTRUN (OpenRC)
#     Se ejecuta UNA vez en el primer arranque real
#     y se auto-deshabilita.
# ─────────────────────────────────────────────
log "Instalando servicio corbex-firstrun..."

# 12a. Script principal del firstrun
mkdir -p /usr/local/sbin
cat > /usr/local/sbin/corbex-firstrun.sh << 'FIRSTRUN_SCRIPT'
#!/bin/bash
# =========================================================
# corbex-firstrun.sh - Tareas de primer arranque
# Se ejecuta una sola vez como servicio OpenRC y se
# auto-deshabilita al finalizar.
# =========================================================
set -x
FLOG="/var/log/corbex-firstrun.log"
echo "$(date '+%Y-%m-%d %H:%M:%S') - FIRSTRUN INICIADO" > "$FLOG"

flog() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$FLOG"; }

# --- PSeInt (requiere red) ---
flog "Instalando PSeInt..."
INSTALL_DIR="/opt/pseint"
cd /tmp
wget --tries=3 --timeout=30 -O pseint.tgz \
    "https://sitsa.dl.sourceforge.net/project/pseint/20250314/pseint-l64-20250314.tgz" 2>>"$FLOG"

# Verificar que el archivo descargado tenga contenido real
if [ -s pseint.tgz ]; then
    tar xf pseint.tgz -C /opt/
    if [ -d "$INSTALL_DIR" ]; then
        cd "$INSTALL_DIR"
        strip wxPSeInt pseint 2>/dev/null
        cat > /usr/share/applications/pseint.desktop << DESKTOP
[Desktop Entry]
Name=PSeInt
Exec=$INSTALL_DIR/wxPSeInt
Icon=$INSTALL_DIR/imgs/icon64.png
Type=Application
Categories=Development;Education;
DESKTOP
        flog "PSeInt instalado correctamente"
    fi
    rm -f /tmp/pseint.tgz
else
    flog "⚠️ No se pudo descargar PSeInt (sin conexión?)"
fi

# --- Antigravity Auto-Updater (requiere red) ---
flog "Configurando repo Antigravity..."
apt-get install -y curl gnupg2 dirmngr --no-install-recommends 2>>"$FLOG" || true
mkdir -p /etc/apt/keyrings

curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg \
    -o /etc/apt/keyrings/antigravity-repo-key.gpg 2>>"$FLOG"

if [ -s /etc/apt/keyrings/antigravity-repo-key.gpg ]; then
    echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" \
        > /etc/apt/sources.list.d/antigravity.list

    apt-get update 2>>"$FLOG" && \
        apt-get install -y antigravity 2>>"$FLOG" || \
        flog "⚠️ No se pudo instalar Antigravity"
else
    flog "⚠️ No se pudo obtener la clave GPG de Antigravity"
fi

# --- Limpieza final (seguro con sistema arrancado) ---
flog "Limpieza final..."
apt-get autoremove --purge -y 2>>"$FLOG" || true
apt-get clean

flog "Configurando directorio inicial de terminal..."
ALUMNO_BASHRC="/home/alumno/.bashrc"
ALUMNO_PROFILE="/home/alumno/.bash_profile"

# Crear si no existen
touch "$ALUMNO_BASHRC" "$ALUMNO_PROFILE"

# Solo redirige si arrancó en / (caso autologin LightDM)
for f in "$ALUMNO_BASHRC" "$ALUMNO_PROFILE"; do
    if ! grep -q "Forzar inicio en HOME" "$f"; then
        echo -e "\n# Forzar inicio en HOME\n[ \"\$PWD\" = \"/\" ] && cd \"\$HOME\"" >> "$f"
    fi
done

chown alumno:alumno "$ALUMNO_BASHRC" "$ALUMNO_PROFILE"
# --- Auto-deshabilitarse ---
flog "Deshabilitando servicio firstrun..."
rc-update del corbex-firstrun default 2>/dev/null || true

flog "FIRSTRUN FINALIZADO OK"
exit 0
FIRSTRUN_SCRIPT
chmod +x /usr/local/sbin/corbex-firstrun.sh

# 12b. Init script OpenRC
cat > /etc/init.d/corbex-firstrun << 'INITSCRIPT'
#!/sbin/openrc-run

description="Corbex OS - Configuración de primer arranque"

depend() {
    need NetworkManager
    after NetworkManager bootmisc
    before login
}

start() {
    ebegin "Ejecutando configuración de primer arranque Corbex..."
    /usr/local/sbin/corbex-firstrun.sh
    eend $?
}
INITSCRIPT
chmod +x /etc/init.d/corbex-firstrun
# En postinst_final.sh, sección 4 (servicios)
rc-update add NetworkManager default 2>/dev/null || true
rc-update add corbex-firstrun default 2>/dev/null || true
# ─────────────────────────────────────────────
log "postinst_final.sh FINALIZADO OK"
echo "$(date '+%Y-%m-%d %H:%M:%S') - FINALIZADO OK" >> "$LOG"
exit 0