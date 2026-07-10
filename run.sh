#!/usr/bin/env bash

set -euo pipefail

IMAGE="aisolation"
# folder where the script is
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# mounted folder
MOUNT_DIR="$(pwd)"

# show help page if needed
usage() {
    echo "Usage: $0"
    echo "Spawn docker container with CTF + AI setup with the current folder mounted."
    echo "-b, --build  rebuild before spawning"
    echo "-h, --help   show this page"
}

for arg in "$@"; do
    if [[ $arg == "-h" || $arg == "--help" ]]; then
        set +x
        usage
        exit 0
    fi
done

FORCE_BUILD=0
if [[ "${1:-}" == "-b" || "${1:-}" == "--build" ]]; then
    FORCE_BUILD=1
    shift
fi

# build image if `--build` or doesn't already exist
if [[ "$FORCE_BUILD" == "1" ]] || ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "[aisolation] Building $IMAGE..."
    docker build \
        --build-arg USER_UID="$(id -u)" \
        --build-arg USER_GID="$(id -g)" \
        -t "$IMAGE" "$SCRIPT_DIR"
fi

echo "[aisolation] Mounted $MOUNT_DIR to /workspace ."
echo "[aisolation] have 'fun'."

ENV_FILE="$SCRIPT_DIR/env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "[aisolation] File $ENV_FILE missing, you need to auth!"
    exit 1
fi

# enter docker
exec docker run --rm -it \
    --hostname aisolation \
    -v "$MOUNT_DIR:/workspace" \
    -w /workspace \
    --env-file $ENV_FILE \
    "$IMAGE" \
    "${@:-bash}"
