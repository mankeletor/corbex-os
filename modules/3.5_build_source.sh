#!/bin/bash
# corbex-build-sources.sh — Generador de sources.list para CorbexOS
#
# Uso: corbex-build-sources.sh [mirror_host]
#
#   Sin argumento: descarga mirror_list.txt de Devuan, elige el más
#                  rápido disponible y genera sources.list.
#   Con argumento: usa ese host directamente (comportamiento original).
#
# Salidas:
#   stdout  → líneas "deb ..." listas para sources.list
#   stderr  → log de progreso (prefijado con #)
#   exit 0  → sources.list válido generado
#   exit 1  → fallo crítico (ningún mirror disponible)
#   exit 2  → error de entorno (curl no disponible, bash requerido)

set -uo pipefail

# --- 0. Verificar entorno ---
if [ -z "${BASH_VERSION:-}" ]; then
    echo "# Error: requiere bash." >&2; exit 2
fi
if ! command -v curl &>/dev/null; then
    echo "# Error: curl no está instalado." >&2; exit 2
fi

# --- Configuración ---
RELEASE="${RELEASE:-excalibur}"
ARCH="${ARCH:-amd64}"
COMPONENTS="main contrib non-free non-free-firmware"
CURL_TIMEOUT="${CURL_TIMEOUT:-8}"

# Mirror propio de la institución — siempre se prueba primero
PREFERRED_MIRROR="dev1mir.registrationsplus.net"

# Mirrors LATAM hardcodeados como candidatos de alta prioridad.
# Fuente: pkgmaster.devuan.org/mirror_list.txt (Active: yes, HTTPS)
# Brasil 20Gb/s (lat ~50ms AR), Chile (lat ~40ms AR)
LATAM_MIRRORS=(
    "devuan.c3sl.ufpr.br"
    "devuan.dcc.uchile.cl"
    "mirror.vpgrp.io"
)

# Fallback global usado si todo lo anterior falla
FALLBACK_MIRROR="pkgmaster.devuan.org"

# Rutas conocidas donde Devuan publica sus índices
KNOWN_PATHS=("/devuan/merged" "/merged" "/packages" "")

# --- Helpers ---
log() { echo "# $*" >&2; }

# Devuelve el tiempo de conexión en ms (entero) o 99999 si falla
probe_ms() {
    local url="$1"
    local result
    result=$(curl -so /dev/null \
        --connect-timeout "$CURL_TIMEOUT" \
        --max-time "$CURL_TIMEOUT" \
        -w "%{http_code} %{time_connect}" \
        "$url" 2>/dev/null) || { echo "99999"; return; }
    local code ms
    code=$(echo "$result" | cut -d' ' -f1)
    ms=$(echo "$result" | cut -d' ' -f2 | awk '{printf "%d", $1*1000}')
    [ "$code" = "200" ] && echo "$ms" || echo "99999"
}

# Encuentra la base URL funcional para un mirror host dado.
# Imprime "https://host/path" o nada si no funciona.
find_base_url() {
    local host="$1"
    local path url ms
    for path in "${KNOWN_PATHS[@]}"; do
        url="https://${host}${path}/dists/${RELEASE}/Release"
        ms=$(probe_ms "$url")
        if [ "$ms" -lt 99999 ]; then
            echo "https://${host}${path}"
            return 0
        fi
    done
    return 1
}

# --- 1. Determinar mirror a usar ---

# Si se pasó un argumento, úsalo directamente (modo legado)
if [ -n "${1:-}" ]; then
    MIRROR_HOST="$1"
    log "Mirror forzado por argumento: $MIRROR_HOST"
    BASE_URL=$(find_base_url "$MIRROR_HOST") || {
        log "Error: $MIRROR_HOST no responde o no tiene suite $RELEASE."
        exit 1
    }
    log "Base URL: $BASE_URL"
else
    # Modo automático: probar preferred + LATAM en paralelo, elegir el más rápido

    log "Seleccionando mirror automáticamente..."

    TMPDIR_PROBE=$(mktemp -d)
    cleanup() { rm -rf "$TMPDIR_PROBE"; }
    trap cleanup EXIT

    # Lanzar probe de todos los candidatos en paralelo
    ALL_MIRRORS=("$PREFERRED_MIRROR" "${LATAM_MIRRORS[@]}" "$FALLBACK_MIRROR")

    for mirror in "${ALL_MIRRORS[@]}"; do
        (
            for path in "${KNOWN_PATHS[@]}"; do
                url="https://${mirror}${path}/dists/${RELEASE}/Release"
                ms=$(probe_ms "$url")
                if [ "$ms" -lt 99999 ]; then
                    echo "${ms} https://${mirror}${path}" > "$TMPDIR_PROBE/${mirror//\//_}"
                    break
                fi
            done
        ) &
    done
    wait

    # Elegir el de menor latencia
    BEST_LINE=$(cat "$TMPDIR_PROBE"/* 2>/dev/null | sort -n | head -1)

    if [ -z "$BEST_LINE" ]; then
        log "Error: ningún mirror disponible."
        exit 1
    fi

    BEST_MS=$(echo "$BEST_LINE" | cut -d' ' -f1)
    BASE_URL=$(echo "$BEST_LINE" | cut -d' ' -f2)
    BEST_HOST=$(echo "$BASE_URL" | sed 's|https://||;s|/.*||')
    log "Mirror seleccionado: $BEST_HOST (${BEST_MS}ms)"
fi

# --- 2. Generar sources.list ---
# Suite principal
echo "deb $BASE_URL $RELEASE $COMPONENTS"

# Suites adicionales: updates y security
# Cada una puede estar en una ruta distinta — se descubren individualmente
for suffix in "-updates" "-security"; do
    SUITE="${RELEASE}${suffix}"
    # Primero intentar la misma base URL (optimización: evita requests extra)
    ms=$(probe_ms "${BASE_URL}/dists/${SUITE}/Release")
    if [ "$ms" -lt 99999 ]; then
        echo "deb $BASE_URL $SUITE $COMPONENTS"
        log "Suite $SUITE: $BASE_URL"
    else
        # Discovery alternativo: probar otras rutas en el mismo host
        HOST=$(echo "$BASE_URL" | sed 's|https://||;s|/.*||')
        ALT_URL=$(find_base_url "$HOST" 2>/dev/null || true)
        # find_base_url siempre prueba la suite principal, necesitamos probar la adicional
        for path in "${KNOWN_PATHS[@]}"; do
            test_url="https://${HOST}${path}/dists/${SUITE}/Release"
            ms=$(probe_ms "$test_url")
            if [ "$ms" -lt 99999 ]; then
                echo "deb https://${HOST}${path} $SUITE $COMPONENTS"
                log "Suite $SUITE: https://${HOST}${path} (ruta alternativa)"
                break
            fi
        done
    fi
done

log "sources.list generado correctamente."
exit 0
