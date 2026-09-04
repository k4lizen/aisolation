#!/usr/bin/env bash

set -euo pipefail

IMAGE="aisolation"
# folder where the script is
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# mounted folder
MOUNT_DIR="$(pwd)"

# make the dev account have a sane id, but actually run
# as root inside the container
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
BUILD_UID="$HOST_UID"
BUILD_GID="$HOST_GID"
DOCKER_USER_ARGS=()
if [[ "$HOST_UID" == "0" ]]; then
    BUILD_UID=1000
    BUILD_GID=1000
    DOCKER_USER_ARGS+=( --user 0:0 --env HOME=/home/dev )
fi

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
STATE_MOUNTS=(
    --mount "type=volume,src=aisolation-nix,dst=/nix"
    --mount "type=volume,src=aisolation-codex,dst=/home/dev/.codex"
    --mount "type=volume,src=aisolation-claude,dst=/home/dev/.claude"
    --mount "type=bind,src=$SCRIPT_DIR/codex-config.toml,dst=/home/dev/.codex/config.toml,readonly"
    --mount "type=bind,src=$SCRIPT_DIR/claude-settings.json,dst=/home/dev/.claude/settings.json,readonly"
    --mount "type=bind,src=$SCRIPT_DIR/agent-instructions.md,dst=/etc/claude-code/CLAUDE.md,readonly"
    --mount "type=bind,src=$SCRIPT_DIR/agent-instructions.md,dst=/home/dev/.codex/AGENTS.md,readonly"
)

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
        --build-arg USER_UID="$BUILD_UID" \
        --build-arg USER_GID="$BUILD_GID" \
        -t "$IMAGE" "$SCRIPT_DIR"
fi

echo "[aisolation] Mounted $MOUNT_DIR to /workspace ."
echo "[aisolation] have 'fun'."

ENV_FILE="$SCRIPT_DIR/env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "[aisolation] File $ENV_FILE missing, you need to auth!"
    exit 1
fi

# pass the same terminal the host uses
# fixes a bug with claude shift-enter sending a prompt instead of a new line
TERM_ARGS=( --env "TERM=${TERM:-xterm-256color}" )
if [[ -n "${COLORTERM:-}" ]]; then
    TERM_ARGS+=( --env "COLORTERM=$COLORTERM" )
fi

# enter docker
# mounting docker.sock and giving perms for it for
#   docker-in-docker (https://jpetazzo.github.io/2015/09/03/do-not-use-docker-in-docker-for-ci/)
# --device=/dev/kvm  to allow running qemu-system setups inside
# We mount named docker-managed volumes that will be shared between all docker runs:
#   + /nix - so the runs don't have to rebuild nix stuff all the time.
#     Since nix is content-addressed, they won't destructively interfere with eachother.
#   + ~/.claude and ~/.codex - so sessions are persisted 
# We then bind-mount ~/.codex/config.toml, ~/.claude/settings.json and agent-instructions.md on top
#   so they are always taken from this repo (and do not grow stale).
# See $STATE_MOUNTS.
# These two:
#    --add-host=host.docker.internal:host-gateway \
#    --env ADB_SERVER_SOCKET=tcp:host.docker.internal:5037 \
# Make it so that the docker can reach an adb server started on the host with `adb -a start-server`.
exec docker run --rm -it \
    "${DOCKER_USER_ARGS[@]}" \
    --hostname aisolation \
    --cap-add=SYS_PTRACE \
    --security-opt seccomp=unconfined \
    --add-host=host.docker.internal:host-gateway \
    --env ADB_SERVER_SOCKET=tcp:host.docker.internal:5037 \
    "${TERM_ARGS[@]}" \
    --volume "$MOUNT_DIR:/workspace" \
    --volume /var/run/docker.sock:/var/run/docker.sock \
    --group-add "$(stat -c '%g' /var/run/docker.sock)" \
    "${STATE_MOUNTS[@]}" \
    "${EXTRA_MOUNTS[@]}" \
    --workdir /workspace \
    --env-file "$ENV_FILE" \
    --device=/dev/kvm \
    "$IMAGE" \
    "${@:-bash}"
