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
Dir::State "$APT_SANDBOX/var/lib/apt";
Dir::Cache "$APT_SANDBOX/var/cache/apt";
Dir::Etc "$APT_SANDBOX/etc/apt";
Dir::Log "$APT_SANDBOX/var/log/apt";
# Configuraciones para Sandbox sin GPG (si fallan las llaves)
Acquire::AllowInsecureRepositories "true";
Acquire::AllowDowngradeToInsecureRepositories "true";
Acquire::Check-Valid-Until "false";
APT::Get::AllowUnauthenticated "true";
Acquire::https::Verify-Peer "false";
APT::Architecture "amd64";
EOF

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
)
PAQUETES_SEMILLA+=("${PAQUETES_CRITICOS[@]}")

# Exportar la lista combinada (Manual + Críticos) para que module 03 la inyecte a la ISO.
printf "%s\n" "${PAQUETES_SEMILLA[@]}" | sort -u > "$BASE_DIR/pkgs_install.txt"

# 0.1 Resolución de Dependencias Recursivas (Cerebro v0.99rc27)
echo "   Resolviendo dependencias recursivas mediante simulación APT..."
# Extraer solo los nombres de paquetes que APT planea instalar
PAQUETES_LISTA_COMPLETA=$(apt-get -c "$APT_SANDBOX/apt.conf" --simulate install "${PAQUETES_SEMILLA[@]}" 2>/dev/null | grep "^Inst " | awk '{print $2}' | sort -u || true)

if [ -z "$PAQUETES_LISTA_COMPLETA" ]; then
    echo "⚠️ Advertencia: APT no pudo resolver dependencias. Usando solo lista manual."
    mapfile -t PAQUETES < <(printf "%s\n" "${PAQUETES_SEMILLA[@]}" | sort -u)
else
    mapfile -t PAQUETES <<< "$PAQUETES_LISTA_COMPLETA"
fi

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

# 1. Identificar paquetes BASE
echo "   Indexando base Netinstall para de-duplicación..."
BASE_PKGS_FILE="$WORKDIR/base_packages.txt"
if [ -f "$ISO_HOME/dists/excalibur/main/binary-amd64/Packages" ]; then
    grep "^Package: " "$ISO_HOME/dists/excalibur/main/binary-amd64/Packages" | cut -d' ' -f2 | sort -u > "$BASE_PKGS_FILE"
else
    touch "$BASE_PKGS_FILE"
fi

# 2. Extraer e Indexar Pool1
EXTRACT_DIR="$WORKDIR/pool1_files"
POOL1_INDEX="$WORKDIR/pool1_index.txt"
echo "   Extrayendo Pool1.iso..."
rm -rf "$EXTRACT_DIR" 2>/dev/null
mkdir -p "$EXTRACT_DIR"
xorriso -osirrox on -indev "$POOL1_ISO" -extract /pool "$EXTRACT_DIR" 2>/dev/null || { echo "❌ Error: Falló la extracción de $POOL1_ISO"; exit 1; }

# Crear índice de búsqueda rápida
find "$EXTRACT_DIR" -name "*.deb" -printf "%p\n" > "$POOL1_INDEX"
DEB_COUNT=$(wc -l < "$POOL1_INDEX")
echo "   ✅ Pool1 indexado ($DEB_COUNT paquetes)."

# 3. Procesamiento Paralelo Optimizado
export EXTRACT_DIR ISO_HOME BASE_PKGS_FILE POOL1_INDEX WARN_LOG APT_SANDBOX PKG_CACHE
process_pkg() {
    local pkg=$1
    local retries=2
    local count=0
    
    # 1. ¿Está en base? (Inmutabilidad estricta)
    if grep -q "^${pkg}$" "$BASE_PKGS_FILE"; then return 0; fi

    # 2. Buscar en índice de Pool1
    local DEB_PATH
    DEB_PATH=$(grep -m1 "/${pkg}_" "$POOL1_INDEX" || true)
    
    if [ -n "$DEB_PATH" ] && [ -f "$DEB_PATH" ]; then
        cp "$DEB_PATH" "$ISO_HOME/pool/local/" || echo "❌ Error copiando $pkg desde Pool1" >> "$WARN_LOG"
    else
        # 3. Buscar en Cache persistente
        local CACHED_DEB
        CACHED_DEB=$(find "$PKG_CACHE" -maxdepth 1 -name "${pkg}_*.deb" -print -quit 2>/dev/null || true)
        if [ -n "$CACHED_DEB" ] && [ -f "$CACHED_DEB" ]; then
            cp "$CACHED_DEB" "$ISO_HOME/pool/local/" || echo "❌ Error copiando $pkg desde Cache" >> "$WARN_LOG"
        else
            # 4. Descarga con Sandbox APT y Re-intento
            while [ "$count" -le "$retries" ]; do
                # Descargar a cache primero con flags de ultra-compatibilidad
                if (cd "$PKG_CACHE" && apt-get -c "$APT_SANDBOX/apt.conf" download "$pkg" -o APT::Get::AllowUnauthenticated=true -o Acquire::AllowInsecureRepositories=true -qq 2>/dev/null); then
                    local NEW_DEB
                    NEW_DEB=$(find "$PKG_CACHE" -maxdepth 1 -name "${pkg}_*.deb" -print -quit 2>/dev/null || true)
                    if [ -n "$NEW_DEB" ]; then
                        cp "$NEW_DEB" "$ISO_HOME/pool/local/"
                        return 0
                    fi
                fi
                ((count++))
                [ "$count" -le "$retries" ] && sleep 1
            done
            echo "❌ No disponible tras $retries reintentos (Sandbox): $pkg" >> "$WARN_LOG"
        fi
    fi
}
export -f process_pkg

echo "   Iniciando copia/descarga paralela..."
printf "%s\n" "${PAQUETES[@]}" | xargs -I {} -P "$THREADS" bash -c 'process_pkg "$@"' _ {}

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

# 4. Generar Índices Apt
echo "   Generando índices de repositorio local..."
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

# ─────────────────────────────────────────────
# EXTRAS OFFLINE: PSeInt + Antigravity + Avidemux + Google Chrome
# Se descargan en build time y se incluyen en la ISO.
# El postinst los instala desde /root/extras/ dentro del chroot.
# ─────────────────────────────────────────────
EXTRAS_DIR="$ISO_HOME/extras"
mkdir -p "$EXTRAS_DIR/antigravity"

# --- PSeInt ---
PSEINT_VER="20250314"
PSEINT_FILE="$EXTRAS_DIR/pseint.tgz"
if [ ! -s "$PSEINT_FILE" ]; then
    echo "   Descargando PSeInt ${PSEINT_VER}..."
    wget --tries=3 --timeout=60 \
        -O "$PSEINT_FILE" \
        "https://downloads.sourceforge.net/project/pseint/${PSEINT_VER}/pseint-l64-${PSEINT_VER}.tgz" || {
        echo "⚠️ No se pudo descargar PSeInt" >> "$WARN_LOG"
        rm -f "$PSEINT_FILE"
    }
    [ -s "$PSEINT_FILE" ] && echo "   ✅ PSeInt descargado ($(du -sh "$PSEINT_FILE" | cut -f1))"
else
    echo "   PSeInt ya en cache, reutilizando ✅"
fi

# --- Antigravity GPG key ---
GPG_FILE="$EXTRAS_DIR/antigravity/antigravity-repo-key.gpg"
if [ ! -s "$GPG_FILE" ]; then
    echo "   Descargando clave GPG de Antigravity..."
    curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg \
        -o "$GPG_FILE" || {
        echo "⚠️ No se pudo descargar clave GPG de Antigravity" >> "$WARN_LOG"
        rm -f "$GPG_FILE"
    }
fi

# --- Antigravity .deb ---
if [ -s "$GPG_FILE" ] && ! ls "$EXTRAS_DIR/antigravity/antigravity_"*.deb 1>/dev/null 2>&1; then
    echo "   Descargando .deb de Antigravity..."
    echo "deb [signed-by=$GPG_FILE] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" \
        > "$TMP_DIR/antigravity-build.list"
    apt-get -c "$APT_SANDBOX/apt.conf" update \
        -o Dir::Etc::sourcelist="$TMP_DIR/antigravity-build.list" \
        -o Dir::Etc::sourceparts="-" \
        -o APT::Get::List-Cleanup=0 -qq 2>/dev/null || true
    (cd "$EXTRAS_DIR/antigravity" && \
        apt-get -c "$APT_SANDBOX/apt.conf" download antigravity \
        -o Dir::Etc::sourcelist="$TMP_DIR/antigravity-build.list" \
        -o Dir::Etc::sourceparts="-" \
        -o APT::Get::AllowUnauthenticated=true -qq 2>/dev/null) || \
        echo "⚠️ No se pudo descargar .deb de Antigravity" >> "$WARN_LOG"
    rm -f "$TMP_DIR/antigravity-build.list"
fi

# --- Avidemux Flatpak Bundle ---
AVIDEMUX_BUNDLE="$EXTRAS_DIR/avidemux.flatpak"
if [ ! -s "$AVIDEMUX_BUNDLE" ]; then
    echo "   Descargando Avidemux como Flatpak bundle offline..."
    if command -v flatpak >/dev/null 2>&1; then
        flatpak remote-add --user --if-not-exists flathub \
            https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
        flatpak install --user --assumeyes --noninteractive flathub \
            org.avidemux.Avidemux 2>/dev/null || true
        flatpak build-bundle \
            "$HOME/.local/share/flatpak/repo" \
            "$AVIDEMUX_BUNDLE" \
            org.avidemux.Avidemux 2>/dev/null || {
            echo "⚠️ No se pudo crear bundle de Avidemux" >> "$WARN_LOG"
            rm -f "$AVIDEMUX_BUNDLE"
        }
        [ -s "$AVIDEMUX_BUNDLE" ] && \
            echo "   ✅ Avidemux bundle generado ($(du -sh "$AVIDEMUX_BUNDLE" | cut -f1))"
    else
        echo "⚠️ flatpak no disponible en sistema de build, omitiendo Avidemux" >> "$WARN_LOG"
    fi
else
    echo "   Avidemux bundle ya en cache, reutilizando ✅"
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

rm -rf "$EXTRACT_DIR" "$APT_SANDBOX"
[ "${TMPDIR_CREATED:-false}" = true ] && rm -rf "$TMP_DIR"
echo "✅ Módulo 04 finalizado exitosamente."