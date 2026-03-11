#!/bin/bash
# CorbexOS - Generador Dinámico de Repositorios
# Uso: ./3.5_build_source.sh "deb.devuan.nz"
#
# Sin set -e: errores manejados explícitamente para no interferir con el discovery.
# Salidas:
#   stdout → contenido del sources.list (solo líneas "deb ...")
#   stderr → mensajes de log/error (prefijados con #)
#   exit 0 → sources.list válido generado
#   exit 1 → fallo crítico (mirror no encontrado o 'main' no disponible)
#   exit 2 → error de entorno (curl no disponible, argumento faltante)

# --- 0. Verificar dependencias de entorno ---
if ! command -v curl &>/dev/null; then
    echo "# Error: 'curl' no está instalado o no está en PATH." >&2
    exit 2
fi

# --- 0.1 Leer config.env si existe ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_ENV="$SCRIPT_DIR/../config.env"
if [ -f "$CONFIG_ENV" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_ENV"
fi

# Valores por defecto (override por config.env o variables de entorno)
RELEASE="${RELEASE:-excalibur}"
ARCH="${ARCH:-amd64}"
CURL_TIMEOUT="${CURL_TIMEOUT:-8}"       # Overrideable — aumentado de 5 a 8s
CURL_MAX_REDIRS="${CURL_MAX_REDIRS:-3}" # Límite de redirects para evitar loops

PROTOCOLS=("https" "http")
RUTAS=("/devuan/merged" "/merged" "")
WANTED_COMPONENTS=("main" "contrib" "non-free" "non-free-firmware")

# --- 1. Leer mirror desde argumento ---
MIRROR_HOST="${1:-}"
if [ -z "$MIRROR_HOST" ]; then
    echo "# Error: No se recibió un mirror como argumento." >&2
    echo "# Uso: $0 <mirror_host>" >&2
    exit 2
fi

# --- Helper: devuelve el HTTP status code de una URL ---
# Limita redirects y tiempo total para evitar falsos positivos con CDNs rotos
http_status() {
    curl -sL \
        --connect-timeout "$CURL_TIMEOUT" \
        --max-time "$(( CURL_TIMEOUT * 3 ))" \
        --max-redirs "$CURL_MAX_REDIRS" \
        -o /dev/null \
        -w "%{http_code}" \
        "$1" 2>/dev/null
}

# --- 2. Discovery: Protocolo y Ruta ---
BASE_URL=""
for proto in "${PROTOCOLS[@]}"; do
    for path in "${RUTAS[@]}"; do
        TEST_URL="${proto}://${MIRROR_HOST}${path}/dists/${RELEASE}/Release"
        STATUS=$(http_status "$TEST_URL")
        if [ "$STATUS" = "200" ]; then
            BASE_URL="${proto}://${MIRROR_HOST}${path}"
            echo "# Mirror encontrado: $BASE_URL" >&2
            break 2
        fi
        echo "# Probando $TEST_URL → HTTP $STATUS" >&2
    done
done

if [ -z "$BASE_URL" ]; then
    echo "# Error: Estructura Devuan (release=$RELEASE) no encontrada en $MIRROR_HOST" >&2
    exit 1
fi

# --- 3. Validación de Componentes ---
# Se validan todos en paralelo para evitar race conditions en CDNs con failover:
# cada componente se chequea en el mismo ciclo de tiempo, no secuencialmente.
FINAL_COMPONENTS=()
FAILED_COMPONENTS=()

validate_component() {
    local comp="$1"
    local base_url="$2"
    local release="$3"
    local arch="$4"
    local check_url="${base_url}/dists/${release}/${comp}/binary-${arch}/Packages.gz"
    local status
    status=$(http_status "$check_url")
    if [ "$status" = "200" ]; then
        echo "OK:$comp"
    else
        echo "FAIL:$comp:$status"
    fi
}

export -f http_status validate_component

# Lanzar validaciones en paralelo y recolectar resultados ordenados
VALIDATION_RESULTS=()
while IFS= read -r result; do
    VALIDATION_RESULTS+=("$result")
done < <(
    printf "%s\n" "${WANTED_COMPONENTS[@]}" | \
    xargs -I{} -P4 bash -c 'validate_component "$@"' _ {} "$BASE_URL" "$RELEASE" "$ARCH"
)

# Procesar resultados respetando el orden original de WANTED_COMPONENTS
for comp in "${WANTED_COMPONENTS[@]}"; do
    matched=""
    for result in "${VALIDATION_RESULTS[@]}"; do
        if [[ "$result" == "OK:${comp}" ]]; then
            matched="ok"
            break
        fi
    done
    if [ -n "$matched" ]; then
        FINAL_COMPONENTS+=("$comp")
        echo "# Componente validado: $comp" >&2
    else
        status=$(printf "%s\n" "${VALIDATION_RESULTS[@]}" | grep "^FAIL:${comp}:" | cut -d: -f3)
        FAILED_COMPONENTS+=("$comp")
        echo "# Componente no disponible (ignorado): $comp [HTTP ${status:-?}]" >&2
    fi
done

# Validación mínima: 'main' es obligatorio
if [[ ! " ${FINAL_COMPONENTS[*]} " =~ " main " ]]; then
    echo "# Error: Mirror incompleto — componente 'main' no hallado." >&2
    exit 1
fi

# Advertencia si faltan componentes esperados (no bloquea, pero informa al caller)
if [ ${#FAILED_COMPONENTS[@]} -gt 0 ]; then
    echo "# Advertencia: Componentes no disponibles en este mirror: ${FAILED_COMPONENTS[*]}" >&2
fi

# --- 4. Detectar suites opcionales (-updates, -security) ---
EXTRA_SUITES=()
for suite_suffix in "-updates" "-security"; do
    SUITE_URL="$BASE_URL/dists/${RELEASE}${suite_suffix}/Release"
    STATUS=$(http_status "$SUITE_URL")
    if [ "$STATUS" = "200" ]; then
        EXTRA_SUITES+=("${RELEASE}${suite_suffix}")
        echo "# Suite adicional disponible: ${RELEASE}${suite_suffix}" >&2
    fi
done

# --- 5. Generar sources.list a stdout ---
# SOLO líneas "deb ..." van a stdout para que el caller pueda capturar limpiamente.
# Los comentarios informativos van a stderr.
COMP_STRING="${FINAL_COMPONENTS[*]}"

echo "deb $BASE_URL $RELEASE $COMP_STRING"
for suite in "${EXTRA_SUITES[@]}"; do
    echo "deb $BASE_URL $suite $COMP_STRING"
done

echo "# sources.list generado correctamente (${#FINAL_COMPONENTS[@]} componentes, $((1 + ${#EXTRA_SUITES[@]})) suites)." >&2
exit 0