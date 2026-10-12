#!/bin/bash
# modules/04_repo_local.sh
# Lógica Complementaria Robusta v0.99rc26
set -euo pipefail

# Cargar configuración y asegurar BASE_DIR
if [ -z "${BASE_DIR:-}" ]; then
    BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

if [ -f "$BASE_DIR/config.env" ]; then
    source "$BASE_DIR/config.env"
else
    echo "❌ Error: config.env no encontrado en $BASE_DIR"
    exit 1
fi

# Redirección de logs (Cerebro v0.99rc25)
# Usar WORKDIR de config.env o fallback al directorio actual
WORKDIR="${WORKDIR:-$BASE_DIR/custom_corbex}"
PKG_CACHE="$BASE_DIR/pkg_cache"
LOG_FILE="$WORKDIR/logs/04_repo_local.log"
WARN_LOG="$WORKDIR/logs/warnings.log"
TMP_DIR=$(mktemp -d)
TMPDIR_CREATED=true
mkdir -p "$WORKDIR/logs" "$PKG_CACHE" "$TMP_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

# Manejo de parámetros
CLEAN_MODE=false
for arg in "$@"; do
    if [ "$arg" == "--clean" ]; then
        CLEAN_MODE=true
        break
    fi
done

if [ "$CLEAN_MODE" = true ]; then
    echo "[Clean] Vaciando caché de paquetes ($PKG_CACHE)..."
    # Borrar solo archivos .deb para no romper el directorio si está montado o algo similar
    find "$PKG_CACHE" -name "*.deb" -type f -delete
fi

# Optimización de hilos (Max segura)
CPU_COUNT=$(nproc)
THREADS=$((CPU_COUNT + 1))
[ "$THREADS" -gt 8 ] && THREADS=8
echo "   Utilizando $THREADS hilos para procesamiento paralelo."

# --- CONFIGURACIÓN DE SANDBOX APT (Multi-distro support) ---
echo "   Configurando entorno APT aislado..."
APT_SANDBOX="$WORKDIR/apt-temp"
# Estructura profunda para evitar errores de APT
mkdir -p "$APT_SANDBOX/var/lib/apt/lists/partial"
mkdir -p "$APT_SANDBOX/var/cache/apt/archives/partial"
mkdir -p "$APT_SANDBOX/etc/apt/preferences.d"
mkdir -p "$APT_SANDBOX/etc/apt/apt.conf.d"
mkdir -p "$APT_SANDBOX/etc/apt/sources.list.d"
mkdir -p "$APT_SANDBOX/var/log/apt"

SOURCES_OUTPUT=""
BUILD_SOURCE_EXIT=0
SOURCES_OUTPUT=$("$BASE_DIR/modules/3.5_build_source.sh" "dev1mir.registrationsplus.net" 2>>"$LOG_FILE") || BUILD_SOURCE_EXIT=$?

if [ "$BUILD_SOURCE_EXIT" -ne 0 ] || [ -z "$SOURCES_OUTPUT" ]; then
    echo "⚠️  3.5_build_source.sh falló (exit $BUILD_SOURCE_EXIT). Usando sources.list de fallback." | tee -a "$WARN_LOG"
    SOURCES_OUTPUT="deb http://dev1mir.registrationsplus.net/devuan/merged ${RELEASE:-excalibur} main contrib non-free non-free-firmware\ndeb http://dev1mir.registrationsplus.net/merged ${RELEASE:-excalibur}-security main contrib non-free non-free-firmware"
else
    echo "   ✅ Mirror resuelto correctamente."
fi
echo "$SOURCES_OUTPUT" > "$APT_SANDBOX/etc/apt/sources.list"

# Inyectar llaves GPG del host para evitar errores de validación
mkdir -p "$APT_SANDBOX/etc/apt/trusted.gpg.d"
if [ -f /etc/apt/trusted.gpg ]; then
    cp /etc/apt/trusted.gpg "$APT_SANDBOX/etc/apt/trusted.gpg" || true
fi
if [ -d /etc/apt/trusted.gpg.d ]; then
    cp -r /etc/apt/trusted.gpg.d/* "$APT_SANDBOX/etc/apt/trusted.gpg.d/" || true
fi

cat > "$APT_SANDBOX/apt.conf" << EOF
Dir "$APT_SANDBOX";
Dir::State "var/lib/apt";
Dir::State::status "var/lib/apt/status";
Dir::Cache "var/cache/apt";
Dir::Etc "etc/apt";
Dir::Log "var/log/apt";
# Configuraciones para Sandbox sin GPG (si fallan las llaves)
Acquire::AllowInsecureRepositories "true";
Acquire::AllowDowngradeToInsecureRepositories "true";
Acquire::Check-Valid-Until "false";
APT::Get::AllowUnauthenticated "true";
Acquire::https::Verify-Peer "false";
APT::Architecture "amd64";
EOF

# Asegurar que el archivo status exista y esté vacío para una resolución limpia
touch "$APT_SANDBOX/var/lib/apt/status"

# Exportar APT_CONFIG antes de cualquier llamada a apt-get para aislar al sandbox
# del sistema anfitrión (evita que el host "sepa" paquetes instalados, p. ej. libwoff1)
# y cause red screen 87% por falta de dependencias en el repo offline.
export APT_CONFIG="$APT_SANDBOX/apt.conf"

echo "   Sincronizando índices de Devuan en el sandbox..."
# Forzar actualización ignorando cualquier restricción de seguridad del host
apt-get -c "$APT_SANDBOX/apt.conf" update -o APT::Get::AllowUnauthenticated=true -o Acquire::AllowInsecureRepositories=true -qq || true

# 0. Cargar y Validar paquetes (Usando lista manual como semilla)
echo "   Cargando paquetes base desde $PKGS_MANUAL_FILE..."
PAQUETES_SEMILLA=()
if [ -f "$PKGS_MANUAL_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        pkg=$(echo "$line" | awk '{print $1}' | sed 's/:.*//')
        if [[ "$pkg" =~ ^[a-z0-9][a-z0-9+.-]+$ ]]; then
            PAQUETES_SEMILLA+=("$pkg")
        fi
    done < "$PKGS_MANUAL_FILE"
else
    echo "❌ Error: $PKGS_MANUAL_FILE no encontrado."
    exit 1
fi

# Inyección de paquetes CRÍTICOS (Declarativo)
PAQUETES_CRITICOS=(
    sudo
    wget
    ntpsec-ntpdate
    openntpd
    net-tools
    bash-completion
    python3
    python3-pip
    python3-venv
    mate-menu
    mate-tweak
    mate-desktop-environment-extras
    mate-applets
    flatpak
    xdg-desktop-portal
    xdg-desktop-portal-gtk
    geogebra
    curl
    vlc
    vlc-plugin-base
    libfuse2
    acpid
    acpi-support-base
    xclip
    git
    nodejs
    npm
    tree
    unzip
    simplescreenrecorder
    network-manager
    wpasupplicant
    wireless-tools
    firmware-linux-nonfree
    intel-microcode
    va-driver-all
    usb-modeswitch
    task-laptop
    grub-common
    grub-pc-bin
    grub-efi-amd64-bin
    efibootmgr
    rdate
    libwoff1
)
PAQUETES_SEMILLA+=("${PAQUETES_CRITICOS[@]}")

# 🔥 GRUB-DUAL: Asegurar que ambos GRUBs meta-paquetes estén para la descarga
# pero NO los incluimos en PAQUETES_SEMILLA para no romper la simulación de APT
# ya que grub-pc y grub-efi-amd64 suelen entrar en conflicto.
PAQUETES_ADICIONALES_REPOS=(grub-pc grub-efi-amd64 grub-efi-amd64-signed grub-efi-amd64-unsigned)

# Exportar la lista base (se actualizará tras la resolución)
printf "%s\n" "${PAQUETES_SEMILLA[@]}" | grep -vE "^(grub-pc|grub-efi-amd64|grub-efi-amd64-signed|grub-efi-amd64-unsigned)$" | sort -u > "$BASE_DIR/pkgs_install.txt"

# 0.1 Resolución de Dependencias Recursivas (Cerebro v0.99rc27)
echo "   Resolviendo dependencias recursivas mediante simulación APT..."
# Incluimos los metapaquetes de GRUB para la resolución uno por uno si es necesario, 
# o simplemente los añadimos a la lista final de descarga.
# Excluir los metapaquetes de GRUB de la simulación para evitar el conflicto
# (ya que uno entra en conflicto con el otro, pero queremos ambo (.deb) en el Repo)
PAQUETES_SIMULACION=("${PAQUETES_SEMILLA[@]}")
# Extraer solo los nombres de paquetes que APT planea instalar
PAQUETES_LISTA_COMPLETA=$(apt-get -c "$APT_SANDBOX/apt.conf" --simulate install "${PAQUETES_SIMULACION[@]}" 2>/dev/null | grep "^Inst " | awk '{print $2}' | sort -u || true)

if [ -z "$PAQUETES_LISTA_COMPLETA" ]; then
    echo "⚠️ Advertencia: APT no pudo resolver dependencias. Usando solo lista manual."
    mapfile -t PAQUETES < <(printf "%s\n" "${PAQUETES_SEMILLA[@]}" "${PAQUETES_ADICIONALES_REPOS[@]}" | sort -u)
else
    # Combinar resolución con adicionales forzados para el Repo
    mapfile -t PAQUETES < <(printf "%s\n" "$PAQUETES_LISTA_COMPLETA" "${PAQUETES_ADICIONALES_REPOS[@]}" | tr ' ' '\n' | sort -u)
    
    # 0.1b REFINAMIENTO DE pkgs_install.txt: Usar la lista resuelta para el instalador
    # Esto asegura que d-i pkgsel sepa exactamente qué instalar offline.
    echo "   Refinando pkgs_install.txt con resolución de dependencias completa..."
    printf "%s\n" "$PAQUETES_LISTA_COMPLETA" | grep -vE "^(grub-pc|grub-efi-amd64|grub-efi-amd64-signed|grub-efi-amd64-unsigned)$" | sort -u > "$BASE_DIR/pkgs_install.txt"
fi

# Añadir paquetes personalizados construidos en el script
echo "pseint" >> "$BASE_DIR/pkgs_install.txt"

# 0.2 Generación de pkgs_offline.txt (Refactorizado)
echo "   Generando pkgs_offline.txt consolidado..."

if [ -n "$PAQUETES_LISTA_COMPLETA" ]; then
    # Volcamos la lista resuelta al archivo, un paquete por línea
    echo "$PAQUETES_LISTA_COMPLETA" | tr ' ' '\n' | sort -u > "$BASE_DIR/pkgs_offline.txt"
    echo "✅ pkgs_offline.txt actualizado con $(wc -l < "$BASE_DIR/pkgs_offline.txt") paquetes (base + críticos + dependencias)."
else
    # Fallback: Si APT falló, al menos guardamos la semilla para no quedar en cero
    echo "⚠️ Usando PAQUETES_SEMILLA como fallback para pkgs_offline.txt"
    printf "%s\n" "${PAQUETES_SEMILLA[@]}" | sort -u > "$BASE_DIR/pkgs_offline.txt"
fi

sed -i '/^$/d' "$BASE_DIR/pkgs_offline.txt"

#echo "   ✅ Total de paquetes únicos a procesar (manual + dependencias): ${#PAQUETES[@]}"

# Directorios
mkdir -p "$ISO_HOME/pool/local"
mkdir -p "$ISO_HOME/dists/excalibur/local/binary-amd64"

# 1. Descargar TODOS los paquetes resueltos directamente del mirror online.
#
# NOTA DE DISEÑO (fix pantalla roja 'Franken-repo'):
# Antes se priorizaba Pool1.iso y se salteaban los paquetes presentes en la
# netinstall base. Eso mezclaba versiones viejas (Pool1/base) con dependencias
# resueltas contra el mirror online, generando conflictos imposibles como
#   util-linux-locales (2.41.5) Depende util-linux (>= 2.41.5)
#   pero util-linux 2.41-5devuan2 (viejo) iba a ser instalado
# → pkgsel fallaba con error 100 → pantalla roja.
#
# Ahora: APT resuelve versiones contra el mirror y bajamos exactamente esas
# versiones. Consistencia garantizada, sin mezcla de repositorios.

echo "   Obteniendo URIs exactas resueltas por APT desde el mirror..."
URI_FILE="$WORKDIR/package_uris.txt"
apt-get -c "$APT_SANDBOX/apt.conf" --print-uris --reinstall -y install \
    "${PAQUETES_SIMULACION[@]}" 2>/dev/null \
    | grep "^'" | cut -d"'" -f2 > "$URI_FILE" || true

URI_COUNT=$(wc -l < "$URI_FILE")
if [ "$URI_COUNT" -eq 0 ]; then
    echo "⚠️  APT no devolvió URIs. Abortando descarga de paquetes." | tee -a "$WARN_LOG"
else
    echo "   ✅ $URI_COUNT URIs obtenidas del mirror."
fi

# 2. Descarga en paralelo con cache persistente
export ISO_HOME WARN_LOG PKG_CACHE URI_FILE
fetch_uri() {
    local uri="$1"
    local fname
    fname=$(basename "$uri")
    # Evitar nombres con query string
    fname="${fname%%\?*}"
    # Decodificar percent-encoding de la URL (apt devuelve %2b por '+', %7e por '~')
    # para que el nombre en disco coincida con el que APT buscará al instalar.
    fname=$(printf '%b' "${fname//%/\\x}")

    # 2a. ¿Ya está en pool/local? (idempotencia)
    if [ -f "$ISO_HOME/pool/local/$fname" ]; then
        return 0
    fi

    # 2b. ¿Ya está en el cache persistente? → copiar
    if [ -f "$PKG_CACHE/$fname" ]; then
        cp "$PKG_CACHE/$fname" "$ISO_HOME/pool/local/" 2>/dev/null && return 0
    fi

    # 2c. Descargar al cache y copiar
    local count=0
    while [ "$count" -le 2 ]; do
        if wget -q --tries=2 --timeout=60 -O "$PKG_CACHE/$fname.part" "$uri" 2>/dev/null; then
            mv "$PKG_CACHE/$fname.part" "$PKG_CACHE/$fname"
            cp "$PKG_CACHE/$fname" "$ISO_HOME/pool/local/" 2>/dev/null
            return 0
        fi
        rm -f "$PKG_CACHE/$fname.part"
        ((count++))
        sleep 1
    done
    echo "❌ No se pudo descargar: $fname ($uri)" >> "$WARN_LOG"
    return 1
}
export -f fetch_uri

echo "   Iniciando descarga paralela desde el mirror..."
if [ -s "$URI_FILE" ]; then
    xargs -I {} -P "$THREADS" bash -c 'fetch_uri "$@"' _ {} < "$URI_FILE"
fi

# 3. Marcar los paquetes de la netinstall base que NO se descargaron.
#    Si un paquete sigue en la base y no fue descargado, el instalador lo toma
#    de la netinstall; pero eso solo es seguro cuando la versión coincide.
#    Los que sí descargamos quedan en pool/local y ganan por versión.
echo "   Verificando cobertura base vs mirror..."
BASE_PKGS_FILE="$WORKDIR/base_packages.txt"
if [ -f "$ISO_HOME/dists/excalibur/main/binary-amd64/Packages" ]; then
    grep "^Package: " "$ISO_HOME/dists/excalibur/main/binary-amd64/Packages" | cut -d' ' -f2 | sort -u > "$BASE_PKGS_FILE"
else
    touch "$BASE_PKGS_FILE"
fi
# El nombre del paquete es lo que precede al primer '_' en el nombre del .deb
PUBLICADOS_LOCAL=$(ls "$ISO_HOME/pool/local/"*.deb 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/_.*//' | sort -u)
BASE_SIN_LOCAL=0
while IFS= read -r bpkg; do
    [ -z "$bpkg" ] && continue
    if ! printf "%s\n" "$PUBLICADOS_LOCAL" | grep -qx "$bpkg"; then
        BASE_SIN_LOCAL=$((BASE_SIN_LOCAL+1))
    fi
done < "$BASE_PKGS_FILE"
echo "   ℹ️  Paquetes de la base netinstall no re-descargados: $BASE_SIN_LOCAL"

# Verificación de paquetes críticos post-procesamiento
# Nota: google-chrome-stable se descarga como extra, no via apt — no se verifica aquí
echo "   Verificando paquetes críticos en pool/local..."
PAQUETES_FALTANTES=()
for pkg in firmware-linux-nonfree intel-microcode vlc network-manager; do
    if ! ls "$ISO_HOME/pool/local/${pkg}_"*.deb 1>/dev/null 2>&1; then
        PAQUETES_FALTANTES+=("$pkg")
    fi
done
if [ ${#PAQUETES_FALTANTES[@]} -gt 0 ]; then
    echo "⚠️  Paquetes críticos NO incluidos: ${PAQUETES_FALTANTES[*]}" | tee -a "$WARN_LOG"
else
    echo "   ✅ Todos los paquetes críticos verificados."
fi


# ─────────────────────────────────────────────
# EXTRAS OFFLINE: PSeInt + Antigravity + Avidemux + Google Chrome
# Se descargan en build time y se incluyen en la ISO.
# El postinst los instala desde /root/extras/ dentro del chroot.
# ─────────────────────────────────────────────
EXTRAS_DIR="$ISO_HOME/extras"
mkdir -p "$EXTRAS_DIR/vscode"

# --- PSeInt ---
PSEINT_VER="20250314"
PSEINT_FILE="$EXTRAS_DIR/pseint.tgz"
PSEINT_DEB="$ISO_HOME/pool/local/pseint_${PSEINT_VER}-1_amd64.deb"

if [ ! -s "$PSEINT_DEB" ] && [ ! -s "$ISO_HOME/pool/local/pseint_${PSEINT_VER}-1_amd64.deb" ]; then
    echo "   Construyendo paquete PSeInt ${PSEINT_VER}..."
    if [ ! -s "$PSEINT_FILE" ]; then
        wget --tries=3 --timeout=60 \
            -O "$PSEINT_FILE" \
            "https://downloads.sourceforge.net/project/pseint/${PSEINT_VER}/pseint-l64-${PSEINT_VER}.tgz" || {
            echo "⚠️ No se pudo descargar PSeInt" >> "$WARN_LOG"
            rm -f "$PSEINT_FILE"
        }
    fi

    if [ -s "$PSEINT_FILE" ]; then
        PSEINT_BUILD="$EXTRAS_DIR/pseint_build"
        rm -rf "$PSEINT_BUILD"
        mkdir -p "$PSEINT_BUILD/opt"
        mkdir -p "$PSEINT_BUILD/usr/share/applications"

        tar xf "$PSEINT_FILE" -C "$PSEINT_BUILD/opt/"
        strip --strip-unneeded "$PSEINT_BUILD/opt/pseint/wxPSeInt" "$PSEINT_BUILD/opt/pseint/pseint" 2>/dev/null || true

        cat > "$PSEINT_BUILD/usr/share/applications/pseint.desktop" << DESKTOP
[Desktop Entry]
Name=PSeInt
Exec=/opt/pseint/wxPSeInt
Icon=/opt/pseint/imgs/icon64.png
Type=Application
Categories=Development;Education;
DESKTOP

        # Build deb with dpkg-deb (fully non-interactive, no TTY needed)
        PSEINT_PKG="$PSEINT_BUILD/pkg"
        mkdir -p "$PSEINT_PKG/opt"
        mkdir -p "$PSEINT_PKG/usr/share/applications"
        mkdir -p "$PSEINT_PKG/DEBIAN"

        # Copy files into package staging area
        cp -r "$PSEINT_BUILD/opt/pseint" "$PSEINT_PKG/opt/"
        cp "$PSEINT_BUILD/usr/share/applications/pseint.desktop" "$PSEINT_PKG/usr/share/applications/"

        # Calculate installed size in KB
        INST_SIZE=$(du -sk "$PSEINT_PKG/opt" | cut -f1)

        # Write DEBIAN/control (required by dpkg-deb)
        cat > "$PSEINT_PKG/DEBIAN/control" << CTRL
Package: pseint
Version: ${PSEINT_VER}-1
Architecture: amd64
Maintainer: CorbexOS <corbex@localhost>
Installed-Size: ${INST_SIZE}
Section: education
Priority: optional
Description: PSeInt IDE - Pseudocode interpreter for education
 PSeInt is a tool for students learning algorithmic programming
 through pseudocode and flowcharts.
CTRL

        echo "Construyendo paquete debian de PSeInt con dpkg-deb..."
        DEB_OUT="$ISO_HOME/pool/local/pseint_${PSEINT_VER}-1_amd64.deb"
        dpkg-deb --build "$PSEINT_PKG" "$DEB_OUT"

        if [ -s "$DEB_OUT" ]; then
            echo "   ✅ Paquete PSeInt construido: $(du -sh "$DEB_OUT" | cut -f1)"
        else
            echo "❌ ERROR: dpkg-deb no generó el .deb de PSeInt" | tee -a "$WARN_LOG"
        fi

        rm -rf "$PSEINT_BUILD"
    fi
else
    echo "   PSeInt ya empaquetado en pool/local, reutilizando ✅"
fi

# --- VSCode ---
# Se descarga el .deb oficial de Microsoft desde la URL fijada en config.env.
# Al instalarse vía dpkg agrega automáticamente su propio repo en
# /etc/apt/sources.list.d/vscode.list → los alumnos reciben
# actualizaciones automáticas con apt upgrade.
VSCODE_DEB="$EXTRAS_DIR/vscode/vscode_amd64.deb"

if [ ! -s "$VSCODE_DEB" ]; then
    echo "   Descargando VSCode estable desde Microsoft..."
    wget --tries=3 --timeout=120 \
        -O "$VSCODE_DEB" \
        "${VSCODE_URL}" || {
        echo "⚠️ No se pudo descargar VSCode" >> "$WARN_LOG"
        rm -f "$VSCODE_DEB"
    }
    if [ -s "$VSCODE_DEB" ]; then
        echo "   ✅ VSCode descargado ($(du -sh "$VSCODE_DEB" | cut -f1))"
    fi
else
    echo "   VSCode ya en cache, reutilizando ✅"
fi


# --- Avidemux AppImage (self-contained, no Flatpak runtime needed) ---
AVIDEMUX_VERSION="2.8.1"
AVIDEMUX_APPIMAGE="$EXTRAS_DIR/avidemux_${AVIDEMUX_VERSION}.appImage"
if [ ! -s "$AVIDEMUX_APPIMAGE" ]; then
    echo "   Descargando Avidemux ${AVIDEMUX_VERSION} AppImage..."
    wget --tries=3 --timeout=120 --content-disposition \
        -O "$AVIDEMUX_APPIMAGE" \
        "https://sourceforge.net/projects/avidemux/files/avidemux/${AVIDEMUX_VERSION}/avidemux_${AVIDEMUX_VERSION}.appImage/download" || {
        echo "⚠️ No se pudo descargar Avidemux AppImage" >> "$WARN_LOG"
        rm -f "$AVIDEMUX_APPIMAGE"
    }
    if [ -s "$AVIDEMUX_APPIMAGE" ]; then
        chmod +x "$AVIDEMUX_APPIMAGE"
        echo "   ✅ Avidemux AppImage descargado ($(du -sh "$AVIDEMUX_APPIMAGE" | cut -f1))"
    fi
else
    echo "   Avidemux AppImage ya en cache, reutilizando ✅"
fi

# --- Google Chrome ---
# Se descarga el .deb oficial de Google directamente.
# Al instalarse vía dpkg agrega automáticamente su propio repo en
# /etc/apt/sources.list.d/google-chrome.list → los alumnos reciben
# actualizaciones automáticas con apt upgrade.
CHROME_DEB="$EXTRAS_DIR/google-chrome-stable.deb"
if [ ! -s "$CHROME_DEB" ]; then
    echo "   Descargando Google Chrome estable..."
    wget --tries=3 --timeout=120 \
        -O "$CHROME_DEB" \
        "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" || {
        echo "⚠️ No se pudo descargar Google Chrome" >> "$WARN_LOG"
        rm -f "$CHROME_DEB"
    }
    if [ -s "$CHROME_DEB" ]; then
        echo "   ✅ Google Chrome descargado ($(du -sh "$CHROME_DEB" | cut -f1))"
    fi
else
    echo "   Google Chrome ya en cache, reutilizando ✅"
fi

echo "✅ Extras offline listos en $EXTRAS_DIR"

# 4. Generar Índices Apt
echo "   Generando índices de repositorio local..."
PREV_DIR="$(pwd)"
cd "$ISO_HOME"

dpkg-scanpackages -m pool/local /dev/null | gzip -9c > dists/excalibur/local/binary-amd64/Packages.gz
zcat dists/excalibur/local/binary-amd64/Packages.gz > dists/excalibur/local/binary-amd64/Packages

# Generar archivo Release con checksums MD5
echo "   Generando Release con checksums MD5..."
cat > "dists/excalibur/local/binary-amd64/Release" << EOF
Origin: Devuan CorbexOS
Label: CorbexOS Local Repo
Suite: excalibur
Codename: excalibur
Date: $(date -Ru)
Architectures: amd64
Components: local
Description: Paquetes Complementarios CorbexOS

MD5Sum:
$(find "dists/excalibur/local/binary-amd64" -type f \( -name "Packages*" -o -name "Release" \) -printf "%P\n" | grep -v "^Release$" | while read -r f; do
    printf " %s %16d %s\n" "$(md5sum "dists/excalibur/local/binary-amd64/$f" | cut -d' ' -f1)" "$(stat -c%s "dists/excalibur/local/binary-amd64/$f")" "$f"
done)
SHA256:
$(find "dists/excalibur/local/binary-amd64" -type f \( -name "Packages*" -o -name "Release" \) -printf "%P\n" | grep -v "^Release$" | while read -r f; do
    printf " %s %16d %s\n" "$(sha256sum "dists/excalibur/local/binary-amd64/$f" | cut -d' ' -f1)" "$(stat -c%s "dists/excalibur/local/binary-amd64/$f")" "$f"
done)
EOF

cd "$PREV_DIR"

# 5. Generar archivo de versión
echo "   Generando archivos de versión en el root de la ISO..."
BUILD_VERSION="CorbexOS ${ISO_PREFIX} Build $(date '+%Y-%m-%d %H:%M')"
echo "$BUILD_VERSION" > "$ISO_HOME/corbex-version"
echo "$BUILD_VERSION" > "$ISO_HOME/corvex_version"
echo "✅ Archivos de versión creados: $BUILD_VERSION"

rm -rf "$APT_SANDBOX"
[ "${TMPDIR_CREATED:-false}" = true ] && rm -rf "$TMP_DIR"
echo "✅ Módulo 04 finalizado exitosamente."