#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
CONTAINERFILE="${SCRIPT_DIR}/Containerfile.toolbx"

DEFAULT_IMAGE="ceai/aegis_ros"
DEFAULT_VERSION="latest"
FALLBACK_BRANCH="humble-devel"
AEGIS_REPO_URL="https://github.com/AGH-CEAI/aegis_ros.git"
NAME_PREFIX="aegis_ros_dev-"

for cmd in podman toolbox git; do
    command -v "${cmd}" >/dev/null 2>&1 || {
        echo ">>> Error: '${cmd}' not found in PATH." >&2
        exit 1
    }
done

[[ -f "${CONTAINERFILE}" ]] || {
    echo ">>> Error: ${CONTAINERFILE} not found." >&2
    exit 1
}

# --- Helpers ---------------------------------------------------------------

detect_branch() {
    # Branch of the directory the script was called from, not where it lives.
    local branch
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    if [[ -z "${branch}" || "${branch}" == "HEAD" ]]; then
        branch="${FALLBACK_BRANCH}"
    fi
    echo "${branch}"
}

resolve_rev() {
    # Resolve the branch to a commit so the dependency layer is rebuilt only
    # when the branch has actually moved. Falls back to a timestamp.
    local branch="$1" rev
    rev="$(git ls-remote "${AEGIS_REPO_URL}" "${branch}" 2>/dev/null | cut -f1 || true)"
    if [[ -z "${rev}" ]]; then
        echo ">>> Warning: could not resolve '${branch}' on the remote," \
             "disabling layer cache." >&2
        rev="$(date +%s)"
    fi
    echo ">>> ${rev}"
}

build_and_enter() {
    local base_ref="$1" version="$2" branch="$3"
    local derived="localhost/aegis_ros_dev:${version}"
    local name="${NAME_PREFIX}${version}"
    local rev
    rev="$(resolve_rev "${branch}")"

    echo ">>> Building ${derived} from ${base_ref} (${branch} @ ${rev:0:8})..."
    podman build "${SCRIPT_DIR}" \
        --file "${CONTAINERFILE}" \
        --build-arg "BASE_REF=${base_ref}" \
        --build-arg "AEGIS_ROS_TAG=${branch}" \
        --build-arg "AEGIS_ROS_REV=${rev}" \
        -t "${derived}"

    echo ">>> Creating toolbx container ${name}..."
    toolbox create --image "${derived}" "${name}"

    echo ">>> Entering ${name}..."
    exec toolbox enter "${name}"
}

create_new() {
    # One confirmation on the defaults; only ask for details on request.
    local base_image="${DEFAULT_IMAGE}" version="${DEFAULT_VERSION}"
    local branch
    branch="$(detect_branch)"

    echo
    echo ">>>   base image : ${base_image}:${version}"
    echo ">>>   container  : ${NAME_PREFIX}${version}"
    echo ">>>   branch     : ${branch}"
    echo

    read -r -p ">>> Create with these settings? [Y]es / [e]dit / [a]bort: " CONFIRM
    case "${CONFIRM:-y}" in
        [yY]) ;;
        [eE])
            read -r -p ">>> Base image [${base_image}]: " reply
            base_image="${reply:-${base_image}}"
            read -r -p ">>> Image version [${version}]: " reply
            version="${reply:-${version}}"
            read -r -p ">>> aegis_ros branch [${branch}]: " reply
            branch="${reply:-${branch}}"
            ;;
        *)
            echo ">>> Aborted."
            exit 0
            ;;
    esac

    build_and_enter "${base_image}:${version}" "${version}" "${branch}"
}

# --- Existing containers ---------------------------------------------------

mapfile -t EXISTING < <(
    podman ps --all --format '{{.Names}}' \
        --filter "name=^${NAME_PREFIX}" | sort
)

if [[ ${#EXISTING[@]} -eq 0 ]]; then
    echo ">>> No existing ${NAME_PREFIX}* container found."
    create_new
fi

if [[ ${#EXISTING[@]} -eq 1 ]]; then
    TARGET="${EXISTING[0]}"
else
    echo ">>> Found ${#EXISTING[@]} aegis_ros_dev containers:"
    for i in "${!EXISTING[@]}"; do
        printf '  %d) %-32s %s\n' "$((i + 1))" "${EXISTING[i]}" \
            "$(podman inspect -f '{{.State.Status}}' "${EXISTING[i]}")"
    done
    read -r -p ">>> Select [1]: " SEL
    SEL="${SEL:-1}"
    if ! [[ "${SEL}" =~ ^[0-9]+$ ]] || ((SEL < 1 || SEL > ${#EXISTING[@]})); then
        echo ">>> Invalid selection." >&2
        exit 1
    fi
    TARGET="${EXISTING[SEL - 1]}"
fi

TARGET_VERSION="${TARGET#"${NAME_PREFIX}"}"
TARGET_IMAGE="localhost/aegis_ros_dev:${TARGET_VERSION}"
TARGET_STATE="$(podman inspect -f '{{.State.Status}}' "${TARGET}")"

echo ">>> Container '${TARGET}' exists (state: ${TARGET_STATE})."
read -r -p ">>> [J]oin / [r]ecreate / [c]leanup / [n]ew: " ACTION

case "${ACTION:-j}" in
    [jJ])
        echo ">>> Entering ${TARGET}..."
        exec toolbox enter "${TARGET}"
        ;;
    [rR])
        BRANCH="$(detect_branch)"
        read -r -p ">>> aegis_ros branch [${BRANCH}]: " REPLY_BRANCH
        BRANCH="${REPLY_BRANCH:-${BRANCH}}"
        echo ">>> Removing ${TARGET}..."
        toolbox rm --force "${TARGET}"
        build_and_enter "${DEFAULT_IMAGE}:${TARGET_VERSION}" \
            "${TARGET_VERSION}" "${BRANCH}"
        ;;
    [cC])
        echo ">>> Removing ${TARGET}..."
        toolbox rm --force "${TARGET}"
        if podman image exists "${TARGET_IMAGE}"; then
            read -r -p ">>> Also remove image ${TARGET_IMAGE}? (y/N): " RM_IMAGE
            case "${RM_IMAGE}" in
                [yY]) podman rmi "${TARGET_IMAGE}" ;;
            esac
        fi
        echo ">>> Cleanup done."
        exit 0
        ;;
    [nN])
        create_new
        ;;
    *)
        echo ">>> Unknown option '${ACTION}', aborting." >&2
        exit 1
        ;;
esac
