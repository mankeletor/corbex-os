#!/bin/bash
# CorbexOS - Generador dinámico de sources.list
# Uso: ${0##*/} "dev1mir.registrationsplus.net"
# Nombre en ISO: corbex-build-sources.sh
# Requiere: bash (usa export -f, arrays asociativos, process substitution)
# Sin set -e: errores manejados explícitamente para no interferir con el discovery.
#
# Salidas:
#   stdout → líneas "deb ..." y "deb-src ..." listas para sources.list
#   stderr → mensajes de log/error (prefijados con #)
#   exit 0 → sources.list válido generado
#   exit 1 → fallo crítico (mirror no encontrado o 'main' no disponible)
#   exit 2 → error de entorno (curl no disponible, argumento faltante)

# --- 0. Dependencias mínimas ---
if ! command -v curl &>/dev/null; then
    echo "# Error: 'curl' no está instalado o no está en PATH." >&2
    exit 2
fi

if [ -z "${BASH_VERSION:-}" ]; then
    echo "# Error: Este script requiere bash, no sh u otro shell." >&2
    exit 2
fi

# Carga condicional: entorno build usa _common.sh, entorno target carga directo
COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$COMMON_DIR/_common.sh" ]; then
    source "$COMMON_DIR/_common.sh"
else
    CONFIG_ENV="$COMMON_DIR/../config.env"
    [ -f "$CONFIG_ENV" ] && source "$CONFIG_ENV"
fi

# Valores por defecto (override por config.env o entorno)
RELEASE="${RELEASE:-excalibur}"
ARCH="${ARCH:-amd64}"
# Timeout: hasta 36s por request (12s connect + 24s max-time)
CURL_TIMEOUT="${CURL_TIMEOUT:-12}"
CURL_MAX_REDIRS="${CURL_MAX_REDIRS:-3}"

# Configuración de discovery
PROTOCOLS=("https" "http")
RUTAS=("/devuan/merged" "/merged" "")
COMPONENTES_BUSCADOS=("main" "contrib" "non-free" "non-free-firmware")
SUFIJOS_SUITES_EXTRA=("-security" "-updates")

# Limpieza al salir
VALIDATION_TMPDIR=""
cleanup() { [ -n "$VALIDATION_TMPDIR" ] && rm -rf "$VALIDATION_TMPDIR"; }
trap cleanup EXIT

# --- 1. Mirror desde argumento ---
MIRROR_HOST="${1:-}"
if [ -z "$MIRROR_HOST" ]; then
    echo "# Error: No se recibió un mirror como argumento." >&2
    echo "# Uso: $0 <mirror_host>" >&2
    exit 2
fi

# Helper: HTTP status code de una URL
http_status() {
    curl -sL \
        --connect-timeout "$CURL_TIMEOUT" \
        --max-time "$(( CURL_TIMEOUT * 3 ))" \
        --max-redirs "$CURL_MAX_REDIRS" \
        -o /dev/null -w "%{http_code}" "$1" 2>/dev/null
}

# Helper: encuentra la URL base para una suite
# Si se pasa un hint (URL de la suite principal), lo prueba primero
# para evitar hasta 6 requests HTTP innecesarios.
find_suite_base_url() {
    local suite="$1"
    local hint="${2:-}"
    local proto path test_url status

    if [ -n "$hint" ]; then
        test_url="${hint}/dists/${suite}/Release"
        status=$(http_status "$test_url")
        echo "# [hint] $test_url → HTTP $status" >&2
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

# --- 3. Validación de componentes en paralelo ---
# Cada worker escribe en su propio archivo para evitar race conditions
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

# Hilos dinámicos: CPU + 1, máximo 8
THREADS=$(( $(nproc) + 1 ))
[ "$THREADS" -gt 8 ] && THREADS=8

printf "%s\n" "${COMPONENTES_BUSCADOS[@]}" | \
    xargs -I{} -P "$THREADS" bash -c 'validate_component "$@"' _ \
        {} "$BASE_URL" "$RELEASE" "$ARCH" "$VALIDATION_TMPDIR"

# Recolectar resultados en orden determinístico
COMPONENTES_OK=()
COMPONENTES_FALLIDOS=()
for comp in "${COMPONENTES_BUSCADOS[@]}"; do
    result_file="$VALIDATION_TMPDIR/$comp"
    if [ -f "$result_file" ]; then
        result=$(cat "$result_file")
    else
        result="FAIL:${comp}:timeout"
    fi

    if [[ "$result" == "OK:${comp}" ]]; then
        COMPONENTES_OK+=("$comp")
        echo "# Componente validado: $comp" >&2
    else
        status=$(echo "$result" | cut -d: -f3)
        COMPONENTES_FALLIDOS+=("$comp")
        echo "# Componente no disponible: $comp [HTTP ${status:-?}]" >&2
    fi
done

# 'main' siempre obligatorio
if [[ ! " ${COMPONENTES_OK[*]} " =~ " main " ]]; then
    echo "# Error: Mirror incompleto — componente 'main' no hallado en $BASE_URL." >&2
    exit 1
fi

if [ ${#COMPONENTES_FALLIDOS[@]} -gt 0 ]; then
    echo "# Advertencia: Componentes no disponibles: ${COMPONENTES_FALLIDOS[*]}" >&2
fi

COMP_STRING="${COMPONENTES_OK[*]}"

# --- 4. Discovery de suites adicionales ---
# Cada suite puede tener diferente URL base (ej. security suele estar en /merged)
# Se pasa BASE_URL como hint para optimizar
declare -A URLS_SUITES
for suffix in "${SUFIJOS_SUITES_EXTRA[@]}"; do
    SUITE_NAME="${RELEASE}${suffix}"
    echo "# Buscando suite adicional: $SUITE_NAME" >&2
    SUITE_BASE=$(find_suite_base_url "$SUITE_NAME" "$BASE_URL") || true
    if [ -n "$SUITE_BASE" ]; then
        URLS_SUITES["$SUITE_NAME"]="$SUITE_BASE"
        echo "# Suite adicional encontrada: $SUITE_NAME → $SUITE_BASE" >&2
    else
        echo "# Suite adicional no disponible: $SUITE_NAME" >&2
    fi
done

# --- 5. Generar sources.list a stdout ---
echo "deb $BASE_URL $RELEASE $COMP_STRING"
echo "deb-src $BASE_URL $RELEASE $COMP_STRING"

for suffix in "${SUFIJOS_SUITES_EXTRA[@]}"; do
    SUITE_NAME="${RELEASE}${suffix}"
    if [ -n "${URLS_SUITES[$SUITE_NAME]:-}" ]; then
        echo "deb ${URLS_SUITES[$SUITE_NAME]} $SUITE_NAME $COMP_STRING"
        echo "deb-src ${URLS_SUITES[$SUITE_NAME]} $SUITE_NAME $COMP_STRING"
    fi
done

echo "# sources.list generado: $RELEASE + ${#URLS_SUITES[@]} suites extra (deb + deb-src)." >&2
exit 0
