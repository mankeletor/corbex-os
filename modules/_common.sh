#!/bin/bash
# _common.sh - Bootstrap compartido para módulos CorbexOS
# Source: source "$(dirname "$0")/_common.sh"

[ -n "${BASE_DIR:-}" ] || BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd)"

CONFIG_ENV="$BASE_DIR/config.env"
if [ -f "$CONFIG_ENV" ]; then
    set -a; source "$CONFIG_ENV"; set +a
else
    echo "Error: $CONFIG_ENV no encontrado"
    exit 1
fi
