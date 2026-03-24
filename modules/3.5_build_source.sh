#!/bin/bash
# CorbexOS - Generador Dinámico de Repositorios
# Uso: ${0##*/} "dev1mir.registrationsplus.net"
#
# Requiere: bash (usa export -f, arrays asociativos, process substitution)
# Sin set -e: errores manejados explícitamente para no interferir con el discovery.
#
# Salidas:
#   stdout → líneas "deb ..." y "deb-src ..." listas para sources.list
#   stderr → mensajes de log/error (prefijados con #)
#   exit 0 → sources.list válido generado
#   exit 1 → fallo crítico (mirror no encontrado o 'main' no disponible)
#   exit 2 → error de entorno (curl no disponible, argumento faltante)

# --- 0. Verificar dependencias de entorno ---
if ! command -v curl &>/dev/null; then
    echo "# Error: 'curl' no está instalado o no está en PATH." >&2
    exit 2
fi

# Verificar bash explícitamente (export -f y arrays asociativos requieren bash)
if [ -z "${BASH_VERSION:-}" ]; then
    echo "# Error: Este script requiere bash, no sh u otro shell." >&2
    exit 2
fi

# --- 0.1 Leer config.env si existe ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_ENV="$SCRIPT_DIR/../config.env"
if [ -f "$CONFIG_ENV" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_ENV"
fi

# Valores por defecto (override por config.env o entorno)
RELEASE="${RELEASE:-excalibur}"
ARCH="${ARCH:-amd64}"
# Timeout aumentado a 12s para tolerar mirrors escolares lentos.
# max-time = CURL_TIMEOUT * 3 (36s total por request)
CURL_TIMEOUT="${CURL_TIMEOUT:-12}"
CURL_MAX_REDIRS="${CURL_MAX_REDIRS:-3}"

# Rutas conocidas del mirror — orden importante: más específica primero
PROTOCOLS=("https" "http")
RUTAS=("/devuan/merged" "/merged" "")
WANTED_COMPONENTS=("main" "contrib" "non-free" "non-free-firmware")

# Suites adicionales a detectar (cada una hace su propio discovery de ruta)
EXTRA_SUITE_SUFFIXES=("-security" "-updates")

# Directorio temporal para resultados de validación paralela (evita race conditions)
VALIDATION_TMPDIR=""

cleanup() {
    [ -n "$VALIDATION_TMPDIR" ] && rm -rf "$VALIDATION_TMPDIR"
}
trap cleanup EXIT

# --- 1. Leer mirror desde argumento ---
MIRROR_HOST="${1:-}"
if [ -z "$MIRROR_HOST" ]; then
    echo "# Error: No se recibió un mirror como argumento." >&2
    echo "# Uso: $0 <mirror_host>" >&2
    exit 2
fi

# --- Helper: devuelve el HTTP status code de una URL ---
http_status() {
    curl -sL \
        --connect-timeout "$CURL_TIMEOUT" \
        --max-time "$(( CURL_TIMEOUT * 3 ))" \
        --max-redirs "$CURL_MAX_REDIRS" \
        -o /dev/null \
        -w "%{http_code}" \
        "$1" 2>/dev/null
}

# --- Helper: encuentra la base URL de una suite dada ---
# Si BASE_URL_HINT está definido, lo prueba primero antes del discovery completo
# para evitar hasta 6 requests HTTP innecesarios en suites adicionales.
# Imprime la URL encontrada a stdout, o nada si no la encuentra.
# Uso: find_suite_base_url "excalibur-security" ["https://mirror/devuan/merged"]
find_suite_base_url() {
    local suite="$1"
    local hint="${2:-}"
    local proto path test_url status

    # Optimización: si se pasa un hint (la URL que ya funcionó para la suite
    # principal), probarlo primero antes de hacer el discovery completo.
    if [ -n "$hint" ]; then
        test_url="${hint}/dists/${suite}/Release"
        status=$(http_status "$test_url")
        echo "# [hint] Probando $test_url → HTTP $status" >&2
        if [ "$status" = "200" ]; then
            echo "$hint"
            return 0
        fi
    fi

    # Discovery completo: 2 protocolos × 3 rutas = hasta 6 requests
    for proto in "${PROTOCOLS[@]}"; do
        for path in "${RUTAS[@]}"; do
            test_url="${proto}://${MIRROR_HOST}${path}/dists/${suite}/Release"
            status=$(http_status "$test_url")
            echo "# Probando $test_url → HTTP $status" >&2
            if [ "$status" = "200" ]; then
                echo "${proto}://${MIRROR_HOST}${path}"
                return 0
            fi
        done
    done
    return 1
}

# --- 2. Discovery de suite principal ---
echo "# Buscando suite principal: $RELEASE" >&2
BASE_URL=$(find_suite_base_url "$RELEASE") || {
    echo "# Error: Suite '$RELEASE' no encontrada en $MIRROR_HOST" >&2
    exit 1
}
echo "# Suite principal encontrada: $BASE_URL" >&2

# --- 3. Validación de componentes ---
# Cada worker escribe su resultado en un archivo temporal propio para
# evitar race conditions de escritura concurrente a stdout con xargs -P.
# export -f requiere bash — verificado en sección 0.
validate_component() {
    local comp="$1" base_url="$2" release="$3" arch="$4" tmpdir="$5"
    local check_url="${base_url}/dists/${release}/${comp}/binary-${arch}/Packages.gz"
    local status
    status=$(http_status "$check_url")
    if [ "$status" = "200" ]; then
        echo "OK:$comp" > "$tmpdir/$comp"
    else
        echo "FAIL:$comp:$status" > "$tmpdir/$comp"
    fi
}
export CURL_TIMEOUT CURL_MAX_REDIRS
export -f http_status validate_component

VALIDATION_TMPDIR=$(mktemp -d)

# Lanzar workers en paralelo, cada uno escribe en su propio archivo
printf "%s\n" "${WANTED_COMPONENTS[@]}" | \
    xargs -I{} -P4 bash -c 'validate_component "$@"' _ \
        {} "$BASE_URL" "$RELEASE" "$ARCH" "$VALIDATION_TMPDIR"

# Leer resultados en orden determinístico (orden de WANTED_COMPONENTS)
FINAL_COMPONENTS=()
FAILED_COMPONENTS=()
for comp in "${WANTED_COMPONENTS[@]}"; do
    result_file="$VALIDATION_TMPDIR/$comp"
    if [ -f "$result_file" ]; then
        result=$(cat "$result_file")
    else
        result="FAIL:${comp}:timeout"
    fi

    if [[ "$result" == "OK:${comp}" ]]; then
        FINAL_COMPONENTS+=("$comp")
        echo "# Componente validado: $comp" >&2
    else
        status=$(echo "$result" | cut -d: -f3)
        FAILED_COMPONENTS+=("$comp")
        echo "# Componente no disponible (ignorado): $comp [HTTP ${status:-?}]" >&2
    fi
done

# 'main' es obligatorio
if [[ ! " ${FINAL_COMPONENTS[*]} " =~ " main " ]]; then
    echo "# Error: Mirror incompleto — componente 'main' no hallado en $BASE_URL." >&2
    exit 1
fi

if [ ${#FAILED_COMPONENTS[@]} -gt 0 ]; then
    echo "# Advertencia: Componentes no disponibles: ${FAILED_COMPONENTS[*]}" >&2
fi

COMP_STRING="${FINAL_COMPONENTS[*]}"

# --- 4. Discovery independiente de cada suite adicional ---
# Cada suite puede tener una base URL diferente.
# Confirmado desde sources.list de instalación real de Devuan excalibur:
#   excalibur          → /devuan/merged/
#   excalibur-updates  → /devuan/merged/
#   excalibur-security → /merged          ← ruta distinta
#
# Optimización: se pasa BASE_URL como hint para evitar el discovery completo
# cuando la suite adicional está en la misma ruta que la principal.
declare -A SUITE_BASE_URLS

for suffix in "${EXTRA_SUITE_SUFFIXES[@]}"; do
    SUITE_NAME="${RELEASE}${suffix}"
    echo "# Buscando suite adicional: $SUITE_NAME" >&2
    SUITE_BASE=$(find_suite_base_url "$SUITE_NAME" "$BASE_URL") || true
    if [ -n "$SUITE_BASE" ]; then
        SUITE_BASE_URLS["$SUITE_NAME"]="$SUITE_BASE"
        echo "# Suite adicional encontrada: $SUITE_NAME → $SUITE_BASE" >&2
    else
        echo "# Suite adicional no disponible (ignorada): $SUITE_NAME" >&2
    fi
done

# --- 5. Generar sources.list a stdout ---
# Líneas "deb" y "deb-src" sin comentarios, para que el caller capture limpiamente.
echo "deb $BASE_URL $RELEASE $COMP_STRING"
echo "deb-src $BASE_URL $RELEASE $COMP_STRING"

for suffix in "${EXTRA_SUITE_SUFFIXES[@]}"; do
    SUITE_NAME="${RELEASE}${suffix}"
    if [ -n "${SUITE_BASE_URLS[$SUITE_NAME]:-}" ]; then
        echo "deb ${SUITE_BASE_URLS[$SUITE_NAME]} $SUITE_NAME $COMP_STRING"
        echo "deb-src ${SUITE_BASE_URLS[$SUITE_NAME]} $SUITE_NAME $COMP_STRING"
    fi
done

echo "# sources.list generado: suite principal + ${#SUITE_BASE_URLS[@]} suites adicionales (deb + deb-src)." >&2
exit 0