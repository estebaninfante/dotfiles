#!/usr/bin/env bash
# phoenix.sh — Manage Arize Phoenix (LLM observability)
# Usage: phoenix.sh {up|down|restart|logs|status|update}

set -euo pipefail

COMPOSE_DIR="$HOME/dotfiles/linux/config/arize-phoenix"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"

usage() {
  echo "Usage: $0 {up|down|restart|logs|status|update}"
  echo ""
  echo "Commands:"
  echo "  up       Start Phoenix (detached)"
  echo "  down     Stop Phoenix"
  echo "  restart  Restart Phoenix"
  echo "  logs     Follow logs"
  echo "  status   Show container status"
  echo "  update   Pull latest image and restart"
  exit 1
}

[[ $# -lt 1 ]] && usage

cmd="$1"
shift

case "$cmd" in
  up)
    echo "Starting Arize Phoenix..."
    docker compose -f "$COMPOSE_FILE" up -d
    echo ""
    echo "Phoenix running at: http://localhost:6006"
    echo "OTLP gRPC: localhost:4317"
    echo "OTLP HTTP: localhost:4318"
    ;;
  down)
    echo "Stopping Arize Phoenix..."
    docker compose -f "$COMPOSE_FILE" down
    ;;
  restart)
    echo "Restarting Arize Phoenix..."
    docker compose -f "$COMPOSE_FILE" restart
    ;;
  logs)
    docker compose -f "$COMPOSE_FILE" logs -f "$@"
    ;;
  status)
    docker compose -f "$COMPOSE_FILE" ps
    ;;
  update)
    echo "Pulling latest Phoenix image..."
    docker compose -f "$COMPOSE_FILE" pull
    echo "Recreating container..."
    docker compose -f "$COMPOSE_FILE" up -d
    echo "Updated and running."
    ;;
  *)
    usage
    ;;
esac
