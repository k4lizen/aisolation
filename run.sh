#!/usr/bin/env bash

set -euo pipefail

IMAGE="aisolation"
# folder where the script is
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# mounted folder
MOUNT_DIR="$(pwd)"

# show help page if needed
usage() {
    echo "Usage: aihere [options] [command]"
    echo ""
    echo "Spawn docker container with CTF + AI setup with the current folder mounted."
    echo ""
    echo "-b, --build                  rebuild before spawning"
    echo "-m, --mount SRC[:DST[:ro]]   mount an extra folder (repeatable)."
    echo "                             DST defaults to /ws/<basename of SRC>."
    echo "                             append :ro for a read-only mount (DST required)."
    echo "-h, --help                   show this page"
}

FORCE_BUILD=0
EXTRA_MOUNTS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -b|--build)
            FORCE_BUILD=1
            shift
            ;;
        -m|--mount)
            if [[ $# -lt 2 ]]; then
                echo "[aisolation] $1 requires an argument: SRC[:DST[:ro]]" >&2
                exit 1
            fi
            spec="$2"
            shift 2
            src="${spec%%:*}"      # everything before the first ':'
            rest="${spec#"$src"}"  # ":DST", ":DST:ro" or empty
            rest="${rest#:}"       # "DST", "DST:ro" or empty
            if [[ ! -e "$src" ]]; then
                echo "[aisolation] mount source does not exist: $src" >&2
                exit 1
            fi
            src="$(realpath "$src")"
            if [[ -z "$rest" ]]; then
                rest="/ws/$(basename "$src")"
            fi
            EXTRA_MOUNTS+=( -v "$src:$rest" )
            echo "[aisolation] Mounting $src to ${rest} ."
            ;;
        -*)
            echo "[aisolation] unknown option: $1" >&2
            usage
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

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
# mounting docker.sock for docker-in-docker (https://jpetazzo.github.io/2015/09/03/do-not-use-docker-in-docker-for-ci/)
# --device=/dev/kvm  to allow running qemu-system setups inside
# We mount a named docker-managed volume (aisolation-nix) that will be shared between all dockers, so they
#   don't have to rebuild nix stuff all the time. Since nix is content-addressed, they won't destructively
#   interfere with eachother.
exec docker run --rm -it \
    --hostname aisolation \
    -v "$MOUNT_DIR:/workspace" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    --mount type=volume,src=aisolation-nix,dst=/nix \
    "${EXTRA_MOUNTS[@]}" \
    -w /workspace \
    --env-file $ENV_FILE \
    --device=/dev/kvm \
    "$IMAGE" \
    "${@:-bash}"
