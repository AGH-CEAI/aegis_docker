#!/bin/bash
set -euo pipefail

NAME_PREFIX="aegis_ros_dev-"
IMAGE_REPO="localhost/aegis_ros_dev"

ASSUME_YES=0
for arg in "$@"; do
    case "${arg}" in
        -y | --yes) ASSUME_YES=1 ;;
        -h | --help)
            echo ">>> Usage: $(basename "$0") [-y|--yes]"
            echo ">>> Removes all ${NAME_PREFIX}* toolbx containers."
            exit 0
            ;;
        *)
            echo ">>> Unknown argument '${arg}'. See --help." >&2
            exit 1
            ;;
    esac
done

for cmd in podman toolbox; do
    command -v "${cmd}" >/dev/null 2>&1 || {
        echo ">>> Error: '${cmd}' not found in PATH." >&2
        exit 1
    }
done

confirm() {
    # $1 = question. Returns 0 on yes.
    local reply
    ((ASSUME_YES)) && return 0
    read -r -p ">>> $1 (y/N): " reply
    [[ "${reply}" =~ ^[yY]([eE][sS])?$ ]]
}

# --- Containers ------------------------------------------------------------

mapfile -t CONTAINERS < <(
    podman ps --all --format '{{.Names}}' \
        --filter "name=^${NAME_PREFIX}" | sort
)

if [[ ${#CONTAINERS[@]} -eq 0 ]]; then
    echo ">>> No ${NAME_PREFIX}* containers found."
else
    echo ">>> Containers to remove:"
    for name in "${CONTAINERS[@]}"; do
        printf '  %-32s %s\n' "${name}" \
            "$(podman inspect -f '{{.State.Status}}' "${name}")"
    done

    if confirm "Remove these ${#CONTAINERS[@]} container(s)?"; then
        for name in "${CONTAINERS[@]}"; do
            echo ">>> Removing ${name}..."
            toolbox rm --force "${name}"
        done
    else
        echo ">>> Skipped containers."
    fi
fi

# --- Images ----------------------------------------------------------------

mapfile -t IMAGES < <(
    podman images --format '{{.Repository}}:{{.Tag}}' \
        --filter "reference=${IMAGE_REPO}" | sort
)

if [[ ${#IMAGES[@]} -eq 0 ]]; then
    echo ">>> No ${IMAGE_REPO} images found."
    exit 0
fi

echo
echo ">>> Images:"
printf '  %s\n' "${IMAGES[@]}"

if confirm "Also remove these ${#IMAGES[@]} image(s)?"; then
    FAILED=0
    for image in "${IMAGES[@]}"; do
        echo ">>> Removing ${image}..."
        # An image still referenced by another container cannot be removed;
        # report it instead of aborting the whole cleanup.
        podman rmi "${image}" || {
            echo ">>>   could not remove ${image} (still in use?)" >&2
            FAILED=1
        }
    done
    ((FAILED)) && echo ">>> Some images were left in place."
else
    echo ">>> Skipped images."
fi

echo ">>> Done."
