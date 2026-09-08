#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
CONTAINERFILE="${SCRIPT_DIR}/Containerfile.prod"

BASE_IMAGE="ceai/aegis_ros"
PROD_IMAGE="ceai/aegis_prod"
FALLBACK_BRANCH="humble-devel"
AEGIS_REPO_URL="https://github.com/AGH-CEAI/aegis_ros.git"
AEGIS_REPO_NAME="aegis_ros"
DEFAULT_REGISTRY="geonosis:5000"

IMAGE_VERSION="latest"
CONTAINER_NAME="aegis_ros_prod"
AEGIS_ROS_TAG=""
DO_BUILD=0
FORCE_BUILD=0
WITH_GUI=1
GPU_MODE="auto"
DRY_RUN=0
DO_PUSH=0
DO_RUN=1
ASSUME_YES=0
REGISTRY=""
LAUNCH_ARGS=()

usage() {
    cat << 'EOF'
Usage: run_project.sh [options] [launch arguments]

Options:
  -b, --build            Build the production image before running
  -B, --rebuild          Build ignoring the layer cache
  -v, --version VER      Image version (default: latest)
  -r, --ref REF          aegis_ros branch/tag/commit (default: detected, else humble-devel)
  -n, --name NAME        Container name (default: aegis_ros_prod)
  -p, --push [HOST:PORT] Push the image to a registry (default: geonosis:5000)
  -y, --yes              Skip the confirmation prompt
      --gpu MODE         nvidia | none | auto (default: auto)
      --no-run           Build and/or push only, do not start the container
      --no-gui           Do not forward X11 (implies launch_rviz:=false)
      --dry-run          Print the podman command instead of running it
  -h, --help             This message

Launch arguments are passed straight to:
  ros2 launch aegis_bringup bringup.launch.py ...

  mock_hardware:={false,true}                (default: false)
  launch_rviz:={false,true}                  (default: true)
  disable_cameras:={false,true}              (default: false)
  model_disable_cell:={false,true}           (default: false)
  model_disable_cell_collision:={false,true} (default: false)
  model_disable_cell_led_supports:={false,true} (default: false)

Examples:
  ./run_project.sh --build mock_hardware:=true
  ./run_project.sh --no-gui disable_cameras:=true
  ./run_project.sh shell            # drop into a sourced shell instead
  ./run_project.sh -B --push --no-run
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -b | --build)   DO_BUILD=1 ;;
        -B | --rebuild) DO_BUILD=1; FORCE_BUILD=1 ;;
        -v | --version) IMAGE_VERSION="$2"; shift ;;
        -r | --ref)     AEGIS_ROS_TAG="$2"; shift ;;
        -n | --name)    CONTAINER_NAME="$2"; shift ;;
        -y | --yes)     ASSUME_YES=1 ;;
        -p | --push)
            DO_PUSH=1
            # Optional value: only consume $2 if it looks like a registry
            if [[ "${2:-}" =~ ^[A-Za-z0-9._-]+(:[0-9]+)?(/.*)?$ && "${2:-}" != *:=* ]]; then
                REGISTRY="$2"
                shift
            fi
            ;;
        --gpu)          GPU_MODE="$2"; shift ;;
        --no-run)       DO_RUN=0 ;;
        --no-gui)       WITH_GUI=0 ;;
        --dry-run)      DRY_RUN=1 ;;
        -h | --help)    usage; exit 0 ;;
        --)             shift; LAUNCH_ARGS+=("$@"); break ;;
        -*)             echo ">>> Unknown option '$1'. See --help." >&2; exit 1 ;;
        *)              LAUNCH_ARGS+=("$1") ;;
    esac
    shift
done

command -v podman >/dev/null 2>&1 || {
    echo ">>> Error: 'podman' not found in PATH." >&2
    exit 1
}

PROD_REF="${PROD_IMAGE}:${IMAGE_VERSION}"

# --- Helpers ---------------------------------------------------------------

in_aegis_repo() {
    # True when $PWD is inside an aegis_ros checkout (repo root or any
    # subdirectory). Being in some other git repo does not count.
    local toplevel url
    toplevel="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -n "${toplevel}" ]] || return 1
    [[ "$(basename "${toplevel}")" == "${AEGIS_REPO_NAME}" ]] && return 0
    url="$(git -C "${toplevel}" config --get remote.origin.url 2>/dev/null || true)"
    [[ "${url}" == *"${AEGIS_REPO_NAME}"* ]]
}

detect_branch() {
    local branch=""
    if in_aegis_repo; then
        branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    fi
    if [[ -z "${branch}" || "${branch}" == "HEAD" ]]; then
        branch="${FALLBACK_BRANCH}"
    fi
    echo "${branch}"
}

nvidia_available() {
    # CDI is how modern podman exposes NVIDIA devices. The spec file is
    # generated once on the host with:
    #   sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
    [[ -f /etc/cdi/nvidia.yaml || -f /var/run/cdi/nvidia.yaml ]]
}

image_label() {
    # $1 = image ref, $2 = label key. Empty string when absent.
    podman image inspect --format "{{ index .Config.Labels \"$2\" }}" "$1" 2>/dev/null || true
}

remote_rev() {
    # $1 = ref. Empty string when it cannot be resolved.
    git ls-remote "${AEGIS_REPO_URL}" "$1" 2>/dev/null | cut -f1 || true
}

build_image() {
    [[ -f "${CONTAINERFILE}" ]] || {
        echo ">>> Error: ${CONTAINERFILE} not found." >&2
        exit 1
    }

    # Resolve the ref to a commit so the workspace layer is rebuilt only when
    # the branch has actually moved.
    local rev
    rev="$(remote_rev "${AEGIS_ROS_TAG}")"
    if [[ -z "${rev}" ]]; then
        echo ">>> Could not resolve '${AEGIS_ROS_TAG}' on the remote, disabling layer cache."
        rev="$(date +%s)"
    fi

    local build_cmd=(podman build "${SCRIPT_DIR}"
        --file "${CONTAINERFILE}"
        --build-arg "BASE_REF=${BASE_IMAGE}:${IMAGE_VERSION}"
        --build-arg "AEGIS_ROS_TAG=${AEGIS_ROS_TAG}"
        --build-arg "AEGIS_ROS_REV=${rev}"
        --build-arg "BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        -t "${PROD_REF}")
    ((FORCE_BUILD)) && build_cmd+=(--no-cache)

    echo ">>> Building ${PROD_REF} (${AEGIS_ROS_TAG} @ ${rev:0:8})..."
    "${build_cmd[@]}"
    echo ">>> Built ${PROD_REF}"
    FORCE_BUILD=0
}

prompt_build_settings() {
    # Shows what is about to be built and lets it be edited, mirroring the
    # create-new flow in enter_toolbx.sh. Updates the globals it touches.
    local reply
    while true; do
        echo
        echo ">>>   base image : ${BASE_IMAGE}:${IMAGE_VERSION}"
        echo ">>>   prod image : ${PROD_IMAGE}:${IMAGE_VERSION}"
        echo ">>>   container  : ${CONTAINER_NAME}"
        echo ">>>   branch/ref : ${AEGIS_ROS_TAG}"
        echo

        read -r -p ">>> Build with these settings? [Y]es / [e]dit / [a]bort: " reply
        case "${reply:-y}" in
            [yY]) break ;;
            [eE])
                read -r -p ">>> Base image [${BASE_IMAGE}]: " reply
                BASE_IMAGE="${reply:-${BASE_IMAGE}}"
                read -r -p ">>> Image version [${IMAGE_VERSION}]: " reply
                IMAGE_VERSION="${reply:-${IMAGE_VERSION}}"
                read -r -p ">>> aegis_ros branch/ref [${AEGIS_ROS_TAG}]: " reply
                AEGIS_ROS_TAG="${reply:-${AEGIS_ROS_TAG}}"
                # The version is part of both image references.
                PROD_REF="${PROD_IMAGE}:${IMAGE_VERSION}"
                ;;
            *)
                echo ">>> Aborted."
                exit 0
                ;;
        esac
    done
}

show_provenance() {
    local tag rev built base current
    tag="$(image_label "${PROD_REF}" aegis.ros.tag)"
    rev="$(image_label "${PROD_REF}" aegis.ros.rev)"
    built="$(image_label "${PROD_REF}" aegis.build.date)"
    base="$(image_label "${PROD_REF}" aegis.base.ref)"

    echo
    echo ">>> Image      : ${PROD_REF}"
    echo ">>> Base image : ${base:-unknown}"
    echo ">>> Branch/ref : ${tag:-unknown}"
    echo ">>> Commit     : ${rev:-unknown}"
    echo ">>> Built at   : ${built:-unknown}"

    # Best-effort staleness check against the remote.
    if [[ -n "${tag}" && -n "${rev}" ]]; then
        current="$(remote_rev "${tag}")"
        if [[ -n "${current}" && "${current}" != "${rev}" ]]; then
            echo ">>> NOTE: '${tag}' has moved to ${current:0:8} since this image was built."
        fi
    fi
    echo
}

# --- Build -----------------------------------------------------------------

if [[ -z "${AEGIS_ROS_TAG}" ]]; then
    AEGIS_ROS_TAG="$(detect_branch)"
fi

if ((DO_BUILD == 0)) && ! podman image exists "${PROD_REF}"; then
    echo ">>> ${PROD_REF} not found locally, it has to be built."
    # Only ask when the build was not requested explicitly with -b/-B.
    if ((ASSUME_YES == 0 && DRY_RUN == 0)); then
        prompt_build_settings
    fi
    DO_BUILD=1
fi

((DO_BUILD)) && build_image

# --- Push ------------------------------------------------------------------

if ((DO_PUSH)); then
    podman image exists "${PROD_REF}" || {
        echo ">>> Error: ${PROD_REF} does not exist locally, nothing to push." >&2
        exit 1
    }

    REGISTRY="${REGISTRY:-${DEFAULT_REGISTRY}}"
    REMOTE_REF="${REGISTRY}/${PROD_IMAGE}:${IMAGE_VERSION}"

    echo ">>> Tagging as ${REMOTE_REF}..."
    podman tag "${PROD_REF}" "${REMOTE_REF}"

    echo ">>> Pushing ${REMOTE_REF}..."
    podman push "${REMOTE_REF}"

    echo ">>> Pushed ${REMOTE_REF}"
fi

((DO_RUN)) || exit 0

# --- Confirm ---------------------------------------------------------------

if ((ASSUME_YES == 0 && DRY_RUN == 0)); then
    while true; do
        show_provenance
        read -r -p ">>> Run it? [Y]es / [r]ebuild / [c]leanup and exit / [a]bort: " ACTION
        case "${ACTION:-y}" in
            [yY]) break ;;
            [rR])
                prompt_build_settings
                build_image
                ;;
            [cC])
                echo ">>> Removing ${PROD_REF}..."
                podman rmi --force "${PROD_REF}"
                echo ">>> Cleanup done."
                exit 0
                ;;
            *)
                echo ">>> Aborted."
                exit 0
                ;;
        esac
    done
fi

# --- Run -------------------------------------------------------------------

if podman container exists "${CONTAINER_NAME}"; then
    echo ">>> Error: container '${CONTAINER_NAME}' already exists." >&2
    echo ">>>        podman rm -f ${CONTAINER_NAME}   (or pass --name)" >&2
    exit 1
fi

RUN_CMD=(podman run --rm --interactive --tty
    --name "${CONTAINER_NAME}"
    # ROS 2 discovery and real hardware (Basler GigE, robot controller)
    --network host
    --ipc host
    --env "ROS_DOMAIN_ID=${ROS_DOMAIN_ID:-0}")

# X11 sockets and passed-through device nodes both need this under SELinux.
NEEDS_LABEL_DISABLE=0

if ((WITH_GUI)); then
    if [[ -z "${DISPLAY:-}" ]]; then
        echo ">>> DISPLAY is not set; RViz will not be able to open a window."
    fi
    RUN_CMD+=(--env "DISPLAY=${DISPLAY:-}"
        --env QT_X11_NO_MITSHM=1
        --volume /tmp/.X11-unix:/tmp/.X11-unix:ro)
    NEEDS_LABEL_DISABLE=1
    [[ -d /dev/dri ]] && RUN_CMD+=(--device /dev/dri)
else
    # Do not start RViz if there is nowhere to draw it
    if ! printf '%s\n' ${LAUNCH_ARGS[@]+"${LAUNCH_ARGS[@]}"} | grep -q '^launch_rviz:='; then
        LAUNCH_ARGS+=("launch_rviz:=false")
    fi
fi

# --- GPU -------------------------------------------------------------------

case "${GPU_MODE}" in
    auto)
        if nvidia_available; then
            USE_NVIDIA=1
        else
            USE_NVIDIA=0
            ((WITH_GUI)) && echo ">>> No NVIDIA CDI spec found; RViz will render on the CPU."
        fi
        ;;
    nvidia)
        USE_NVIDIA=1
        nvidia_available || {
            echo ">>> Error: --gpu nvidia requested but no CDI spec found." >&2
            echo ">>>        sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml" >&2
            exit 1
        }
        ;;
    none) USE_NVIDIA=0 ;;
    *)
        echo ">>> Unknown --gpu mode '${GPU_MODE}' (nvidia|none|auto)." >&2
        exit 1
        ;;
esac

if ((USE_NVIDIA)); then
    echo ">>> Using the NVIDIA GPU."
    RUN_CMD+=(--device nvidia.com/gpu=all
        # 'graphics' is what RViz needs; 'compute' alone gives no OpenGL.
        --env NVIDIA_VISIBLE_DEVICES=all
        --env NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics,display
        --env __GLX_VENDOR_LIBRARY_NAME=nvidia)
    NEEDS_LABEL_DISABLE=1
fi

if ((NEEDS_LABEL_DISABLE)); then
    RUN_CMD+=(--security-opt label=disable)
fi

# DepthAI cameras enumerate over USB
[[ -d /dev/bus/usb ]] && RUN_CMD+=(--volume /dev/bus/usb:/dev/bus/usb)

# Note the ${arr[@]+"${arr[@]}"} form: a plain "${arr[@]:-}" would expand an
# empty array to one empty string, which ros2 launch rejects as a malformed
# launch argument.
RUN_CMD+=("${PROD_REF}" ${LAUNCH_ARGS[@]+"${LAUNCH_ARGS[@]}"})

if ((DRY_RUN)); then
    printf '%q ' "${RUN_CMD[@]}"
    echo
    exit 0
fi

echo ">>> Running ${PROD_REF} as ${CONTAINER_NAME}"
exec "${RUN_CMD[@]}"
