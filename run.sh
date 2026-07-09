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
    echo "--build      rebuild before spawning"
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
if [[ "${1:-}" == "--build" ]]; then
    FORCE_BUILD=1
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

# enter docker
exec docker run --rm -it \
    --hostname sandbox \
    -v "$MOUNT_DIR:/workspace" \
    -w /workspace \
    ${ANTHROPIC_API_KEY:+-e ANTHROPIC_API_KEY} \
    "$IMAGE" \
    "${@:-bash}"
