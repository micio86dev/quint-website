#!/usr/bin/env bash

# Starts the complete local Quint stack without modifying existing data.
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
readonly READY_TIMEOUT_SECONDS="${QUINT_READY_TIMEOUT_SECONDS:-90}"

usage() {
  printf '%s\n' "Usage: $(basename "$0") [--detach]"
  printf '%s\n' '  --detach, -d  Start in the background and wait for both HTTP endpoints.'
  printf '%s\n' '  Set QUINT_READY_TIMEOUT_SECONDS to change the detached-mode timeout (default: 90).'
}

wait_for_http() {
  local service_name="$1"
  local url="$2"
  local deadline=$((SECONDS + READY_TIMEOUT_SECONDS))

  while (( SECONDS < deadline )); do
    if curl --fail --silent --max-time 3 "$url" >/dev/null; then
      printf 'Ready: %s (%s)\n' "$service_name" "$url"
      return 0
    fi
    sleep 2
  done

  printf 'Error: %s did not become reachable within %s seconds: %s\n' \
    "$service_name" "$READY_TIMEOUT_SECONDS" "$url" >&2
  docker compose --file "$COMPOSE_FILE" ps >&2 || true
  return 1
}

detach=false
case "${1:-}" in
  '') ;;
  --detach|-d) detach=true ;;
  --help|-h) usage; exit 0 ;;
  *)
    usage >&2
    exit 64
    ;;
  esac

if ! [[ "$READY_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Error: QUINT_READY_TIMEOUT_SECONDS must be a positive integer.\n' >&2
  exit 64
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
  printf 'Error: expected Docker Compose file at %s.\n' "$COMPOSE_FILE" >&2
  exit 1
fi

for required_dir in "$SCRIPT_DIR/quint-website-frontend" "$SCRIPT_DIR/quint-website-backend"; do
  if [[ ! -d "$required_dir" ]]; then
    printf 'Error: required project directory is missing: %s\n' "$required_dir" >&2
    exit 1
  fi
done

if ! command -v docker >/dev/null 2>&1; then
  printf '%s\n' 'Error: Docker Desktop (including Docker Compose v2) is required.' >&2
  exit 127
fi

if ! docker compose version >/dev/null 2>&1; then
  printf '%s\n' 'Error: Docker Compose v2 is not available. Update or start Docker Desktop.' >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  printf '%s\n' 'Error: the Docker daemon is unavailable. Start Docker Desktop and try again.' >&2
  exit 1
fi

printf '%s\n' 'Starting Quint locally...'
printf '%s\n' 'Frontend:  http://localhost:4321'
printf '%s\n' 'Backend:   http://localhost:8090'
printf '%s\n' 'Backoffice: http://localhost:8090/_/'

if [[ "$detach" == true ]]; then
  if ! command -v curl >/dev/null 2>&1; then
    printf '%s\n' 'Error: curl is required to verify detached-mode HTTP readiness.' >&2
    exit 127
  fi
  docker compose --file "$COMPOSE_FILE" up --build --detach
  wait_for_http 'backend health endpoint' 'http://localhost:8090/api/quint/health'
  wait_for_http 'frontend' 'http://localhost:4321/'
  docker compose --file "$COMPOSE_FILE" ps
else
  exec docker compose --file "$COMPOSE_FILE" up --build
fi
