#!/bin/bash
# apply_patches.sh - Aplica todos los fixes de integridad CorbexOS
# Uso: bash apply_patches.sh (desde la raíz del proyecto)
set -euo pipefail

REPO_ROOT="$(pwd)"
PATCH_ERRORS=0

apply() {
    local label="$1"
    local patchfile="$2"

    echo "$patchfile" > /tmp/_corbex_patch.patch

    if patch --dry-run -p0 -d "$REPO_ROOT" < /tmp/_corbex_patch.patch > /dev/null 2>&1; then
        patch -p0 -d "$REPO_ROOT" < /tmp/_corbex_patch.patch > /dev/null
        echo "✅ $label"
    else
        echo "❌ Falló: $label (¿ya aplicado o contexto no coincide?)"
        PATCH_ERRORS=$((PATCH_ERRORS+1))
    fi
    rm -f /tmp/_corbex_patch.patch
}

echo "🔧 Aplicando patches de integridad CorbexOS..."
echo "================================================"


apply "config.env: agregar RELEASE=excalibur" '--- config.env
+++ config.env
@@ -27,6 +27,9 @@
 ISO_VOLID="CORBEX-OS"
 ISO_PREFIX="devuan-corbexos"
 
+# --- RELEASE ---
+RELEASE="excalibur"
+
 # --- ZONA HORARIA Y LOCALE ---
 TIMEZONE="America/Argentina/Cordoba"
 LOCALE="es_AR.UTF-8"
'


apply "main.sh: quitar doble source + comillas en CLEAN_ARG" '--- main.sh
+++ main.sh
@@ -21,7 +21,6 @@
     echo "❌ Error: config.env no encontrado."
     exit 1
 fi
-source ./config.env
 set -a
 source ./config.env
 set +a
@@ -67,7 +66,7 @@
 run_module "02_extract_iso.sh"
 
 # Orden de Dependencia Crítico: 04 antes que 03 (Sincrónico)
-run_module "04_repo_local.sh" $CLEAN_ARG
+run_module "04_repo_local.sh" "$CLEAN_ARG"
 run_module "03_build_initrd.sh"
 
 run_module "05_build_iso.sh"
'


apply "03_build_initrd.sh: fix BASE_DIR + copia pkgs_manual.txt" '--- modules/03_build_initrd.sh
+++ modules/03_build_initrd.sh
@@ -8,7 +8,7 @@
 # Carga de configuración corregida
 if [ -z "$ISO_ORIGINAL" ]; then
     SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
-    source "$BASE_DIR/config.env"
+    source "$SCRIPT_DIR/../config.env"
 fi
 
 # 1. Cargar paquetes desde pkgs_manual.txt (Selección manual para preseed)
@@ -57,6 +57,7 @@
 cp "$BASE_DIR/scripts_aux/postinst_final.sh" ./postinst.sh
 cp "$BASE_DIR/templates/rc.conf" ./rc.conf
 cp "$BASE_DIR/templates/corbex.dconf" ./corbex.dconf
+cp "$BASE_DIR/pkgs_manual.txt" ./pkgs_manual.txt
 
 # --- NUEVO: Script de intervención radical (finish-install) ---
 # Optimizado para RAM: solo lanza apt tras asegurar que el target tiene el repo local
'


apply "04_repo_local.sh: TMP_DIR + exit code + grep Pool1 + verificación" '--- modules/04_repo_local.sh
+++ modules/04_repo_local.sh
@@ -21,6 +21,8 @@
 PKG_CACHE="$BASE_DIR/pkg_cache"
 LOG_FILE="$WORKDIR/logs/04_repo_local.log"
 WARN_LOG="$WORKDIR/logs/warnings.log"
+TMP_DIR=$(mktemp -d)
+TMPDIR_CREATED=true
 mkdir -p "$WORKDIR/logs" "$PKG_CACHE" "$TMP_DIR"
 exec > >(tee -a "$LOG_FILE") 2>&1
 
@@ -54,10 +56,15 @@
 mkdir -p "$APT_SANDBOX/etc/apt/preferences.d"
 mkdir -p "$APT_SANDBOX/var/log/apt"
 
-SOURCES_OUTPUT=$("$BASE_DIR/modules/3.5_build_source.sh" "dev1mir.registrationsplus.net") || true
-if [ -z "$SOURCES_OUTPUT" ]; then
-    echo "⚠️ Advertencia: 3.5_build_source.sh no generó salida. Usando sources.list manual."
-    SOURCES_OUTPUT="deb http://dev1mir.registrationsplus.net/devuan/merged ${RELEASE:-excalibur} main contrib non-free non-free-firmware"
+SOURCES_OUTPUT=""
+BUILD_SOURCE_EXIT=0
+SOURCES_OUTPUT=$("$BASE_DIR/modules/3.5_build_source.sh" "dev1mir.registrationsplus.net" 2>>"$LOG_FILE") || BUILD_SOURCE_EXIT=$?
+
+if [ "$BUILD_SOURCE_EXIT" -ne 0 ] || [ -z "$SOURCES_OUTPUT" ]; then
+    echo "⚠️  3.5_build_source.sh falló (exit $BUILD_SOURCE_EXIT). Usando sources.list de fallback." | tee -a "$WARN_LOG"
+    SOURCES_OUTPUT="deb http://dev1mir.registrationsplus.net/devuan/merged ${RELEASE:-excalibur} main contrib non-free non-free-firmware\ndeb http://dev1mir.registrationsplus.net/merged ${RELEASE:-excalibur}-security main contrib non-free non-free-firmware"
+else
+    echo "   ✅ Mirror resuelto correctamente."
 fi
 echo "$SOURCES_OUTPUT" > "$APT_SANDBOX/etc/apt/sources.list"
 
@@ -189,8 +196,6 @@
 EXTRACT_DIR="$WORKDIR/pool1_files"
 POOL1_INDEX="$WORKDIR/pool1_index.txt"
 # Agregar cerca de donde definís EXTRAS_DIR, antes de usarlo:
-TMP_DIR="${TMP_DIR:-$(mktemp -d)}"
-TMPDIR_CREATED=true
 echo "   Extrayendo Pool1.iso..."
 rm -rf "$EXTRACT_DIR" 2>/dev/null
 mkdir -p "$EXTRACT_DIR"
@@ -213,7 +218,7 @@
 
     # 2. Buscar en índice de Pool1
     local DEB_PATH
-    DEB_PATH=$(grep -m1 "/${pkg}_[0-9]" "$POOL1_INDEX" || true)
+    DEB_PATH=$(grep -m1 "/${pkg}_" "$POOL1_INDEX" || true)
     
     if [ -n "$DEB_PATH" ] && [ -f "$DEB_PATH" ]; then
         cp "$DEB_PATH" "$ISO_HOME/pool/local/" || echo "❌ Error copiando $pkg desde Pool1" >> "$WARN_LOG"
@@ -247,6 +252,20 @@
 echo "   Iniciando copia/descarga paralela..."
 printf "%s\n" "${PAQUETES[@]}" | xargs -I {} -P "$THREADS" bash -c '\''process_pkg "$@"'\'' _ {}
 
+# Verificación de paquetes críticos post-procesamiento
+echo "   Verificando paquetes críticos en pool/local..."
+PAQUETES_FALTANTES=()
+for pkg in chromium firmware-linux-nonfree intel-microcode vlc network-manager; do
+    if ! ls "$ISO_HOME/pool/local/${pkg}_"*.deb 1>/dev/null 2>&1; then
+        PAQUETES_FALTANTES+=("$pkg")
+    fi
+done
+if [ ${#PAQUETES_FALTANTES[@]} -gt 0 ]; then
+    echo "⚠️  Paquetes críticos NO incluidos: ${PAQUETES_FALTANTES[*]}" | tee -a "$WARN_LOG"
+else
+    echo "   ✅ Todos los paquetes críticos verificados."
+fi
+
 # 4. Generar Índices Apt
 echo "   Generando índices de repositorio local..."
 cd "$ISO_HOME"
'


apply "preseed.cfg: grub default + pkgs_manual.txt en late_command" '--- templates/preseed.cfg
+++ templates/preseed.cfg
@@ -106,7 +106,7 @@
 # --------------------
 d-i grub-installer/only_debian boolean true
 d-i grub-installer/with_other_os boolean true
-d-i grub-installer/bootdev string /dev/sda
+d-i grub-installer/bootdev string default
 
 # --------------------
 # POST-INSTALACIÓN (EJECUCIÓN DIRECTA)
@@ -115,6 +115,7 @@
     cp -r /cdrom/extras /target/root/extras || true; \
     cp /rc.conf /target/etc/rc.conf; \
     cp /postinst.sh /target/root/postinst.sh; \
+    cp /pkgs_manual.txt /target/root/pkgs_manual.txt; \
     cp /corbex.dconf /target/root/corbex.dconf; \
     chmod +x /target/root/postinst.sh; \
     in-target /root/postinst.sh
'


apply "corbex.dconf: quitar session-start hardcodeado" '--- templates/corbex.dconf
+++ templates/corbex.dconf
@@ -55,9 +55,6 @@
 [org/mate/desktop/peripherals/keyboard]
 numlock-state='\''off'\''
 
-[org/mate/desktop/session]
-session-start=1772520957
-
 [org/mate/desktop/sound]
 event-sounds=true
 theme-name='\''freedesktop'\''
'

echo "================================================"
if [ "$PATCH_ERRORS" -eq 0 ]; then
    echo "🎉 Todos los patches aplicados correctamente."
else
    echo "⚠️  $PATCH_ERRORS patch(es) fallaron. Revisá los errores arriba."
fi
