#!/bin/bash
# =========================================================
# postinst_final.sh - Versión Final Blindada (v1.0rc1)
# ESFP Córdoba - Optimizado para Netbooks (4GB RAM)
# =========================================================

LOG="/var/log/custom-postinst.log"
echo "$(date '+%Y-%m-%d %H:%M:%S') - postinst_final.sh INICIADO" > "$LOG"
set -x  # Modo debug

echo "=== Optimizando sistema para ESFP Córdoba ==="

# 1. Idioma y locales
echo "es_AR.UTF-8 UTF-8" > /etc/locale.gen
locale-gen es_AR.UTF-8
update-locale LANG=es_AR.UTF-8

# 2. Instalación de paquetes desde Repositorio Local/Mirror
if [ -f /root/pkgs_manual.txt ]; then
    LISTA_PKGS=$(cat /root/pkgs_manual.txt | tr '\n' ' ' | sed 's/  */ /g')
    echo "Instalando paquetes: $LISTA_PKGS"
    apt-get update || echo "⚠️ Falló update local/mirror"
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends --fix-broken $LISTA_PKGS 2>&1 | tee /root/postinst_manual_pkgs.log
fi

# 3. Optimización de Memoria (Swappiness)
echo "vm.swappiness=10" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1 || true

# 4. Limpieza de servicios innecesarios (OpenRC & SysV)
if command -v rc-update >/dev/null; then
    for s in bluetooth cups; do rc-update del $s default 2>/dev/null || true; done
fi

# 5. Configuración de Escritorio MATE (dconf global)
mkdir -p /etc/dconf/profile /etc/dconf/db/local.d
cat > /etc/dconf/profile/user << 'EOF'
user-db:user
system-db:local
EOF

if [ -f /root/esfp.dconf ]; then
    cp /root/esfp.dconf /etc/dconf/db/local.d/01-esfp-custom
    dconf update || echo "Error dconf"
fi

# 5.1 Script de Primer Inicio (Silencioso y Seguro)
cat > /etc/profile.d/esfp-firstrun.sh << 'EOF'
#!/bin/bash
MARKER="$HOME/.config/esfp-firstrun-done"

# Solo actuar si es el usuario alumno y no se hizo antes
if [ "$USER" = "alumno" ] && [ ! -f "$MARKER" ]; then
    # Asegurar que el marcador se cree primero para evitar bucles
    mkdir -p "$(dirname "$MARKER")"
    touch "$MARKER"

    # Agregar 'cd' al .bashrc solo si no existe ya esa línea
    if ! grep -q "^cd$" "$HOME/.bashrc"; then
        echo -e "\n# Forzar inicio en HOME\ncd" >> "$HOME/.bashrc"
    fi
fi
EOF
chmod 644 /etc/profile.d/esfp-firstrun.sh

# 6. INSTALACIÓN DE PSEINT (Offline/Online)
echo "--- Instalando PSeInt ---"
INSTALL_DIR="/opt/pseint"
cd /tmp
wget --tries=2 --timeout=15 -O pseint.tgz "https://sitsa.dl.sourceforge.net/project/pseint/20250314/pseint-l64-20250314.tgz" || true

if [ -f pseint.tgz ]; then
    tar xf pseint.tgz -C /opt/
    cd $INSTALL_DIR
    strip wxPSeInt pseint 2>/dev/null || true
    cat > /usr/share/applications/pseint.desktop << EOF
[Desktop Entry]
Name=PSeInt
Exec=$INSTALL_DIR/wxPSeInt
Icon=$INSTALL_DIR/imgs/icon64.png
Type=Application
Categories=Development;Education;
EOF
fi

# 7. Sudoers RESTRINGIDO (Solo gestión de paquetes)
echo "Configurando sudo restringido..."
if [ -d /etc/sudoers.d ]; then
    echo "alumno ALL=(ALL) NOPASSWD: /usr/bin/apt, /usr/bin/apt-get, /usr/bin/apt-cache, /usr/bin/apt-mark, /usr/bin/dpkg" > /etc/sudoers.d/alumno
    chmod 440 /etc/sudoers.d/alumno
fi

# 7.1 Autologin LightDM
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-autologin.conf << EOF
[Seat:*]
autologin-user=alumno
autologin-user-timeout=0
autologin-session=mate
EOF

# 8. Editor por defecto
update-alternatives --set editor /bin/nano 2>/dev/null || true

# 9. Recuperar rc.conf si existe
[ -f /rc.conf ] && cp /rc.conf /etc/rc.conf

# 10. ANTIGRAVITY AUTO-UPDATER & Limpieza
echo "Configurando Antigravity..."
apt-get install -y curl gnupg2 dirmngr --no-install-recommends
mkdir -p /etc/apt/keyrings
curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg

echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" > /etc/apt/sources.list.d/antigravity.list

apt-get update && apt-get install -y antigravity

# Asegurar el directorio home y el shell para el usuario alumno
chsh -s /bin/bash alumno
usermod -d /home/alumno -m alumno

# Limpieza Final
apt-get purge -y xterm 2>/dev/null || true
apt-get autoremove --purge -y
apt-get clean

echo "$(date '+%Y-%m-%d %H:%M:%S') - FINALIZADO OK" >> "$LOG"
exit 0