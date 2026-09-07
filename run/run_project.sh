#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
CONTAINERFILE="${SCRIPT_DIR}/Containerfile.prod"

BASE_IMAGE="ceai/aegis_ros"
PROD_IMAGE="ceai/aegis_prod"
FALLBACK_BRANCH="humble-devel"
AEGIS_REPO_URL="https://github.com/AGH-CEAI/aegis_ros.git"
DEFAULT_REGISTRY="geonosis:5000"

IMAGE_VERSION="latest"
CONTAINER_NAME="aegis_ros_prod"
AEGIS_ROS_TAG=""
DO_BUILD=0
FORCE_BUILD=0
WITH_GUI=1
DRY_RUN=0
DO_PUSH=0
DO_RUN=1
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
        -p | --push)
            DO_PUSH=1
            # Optional value: only consume $2 if it looks like a registry
            if [[ "${2:-}" =~ ^[A-Za-z0-9._-]+(:[0-9]+)?(/.*)?$ && "${2:-}" != *:=* ]]; then
                REGISTRY="$2"
                shift
            fi
            ;;
        --no-run)       DO_RUN=0 ;;
        --no-gui)       WITH_GUI=0 ;;
        --dry-run)      DRY_RUN=1 ;;
        -h | --help)    usage; exit 0 ;;
        --)             shift; LAUNCH_ARGS+=("$@"); break ;;
        -*)             echo "Unknown option '$1'. See --help." >&2; exit 1 ;;
        *)              LAUNCH_ARGS+=("$1") ;;
    esac
    shift
done

command -v podman >/dev/null 2>&1 || {
    echo "Error: 'podman' not found in PATH." >&2
    exit 1
}

PROD_REF="${PROD_IMAGE}:${IMAGE_VERSION}"

# --- Build -----------------------------------------------------------------

if [[ -z "${AEGIS_ROS_TAG}" ]]; then
    AEGIS_ROS_TAG="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    if [[ -z "${AEGIS_ROS_TAG}" || "${AEGIS_ROS_TAG}" == "HEAD" ]]; then
        AEGIS_ROS_TAG="${FALLBACK_BRANCH}"
    fi
fi

if ((DO_BUILD == 0)) && ! podman image exists "${PROD_REF}"; then
    echo ">>> ${PROD_REF} not found locally, building it."
    DO_BUILD=1
fi

if ((DO_BUILD)); then
    [[ -f "${CONTAINERFILE}" ]] || {
        echo "Error: ${CONTAINERFILE} not found." >&2
        exit 1
    }

    # Resolve the ref to a commit so the workspace layer is rebuilt only when
    # the branch has actually moved.
    AEGIS_ROS_REV="$(git ls-remote "${AEGIS_REPO_URL}" "${AEGIS_ROS_TAG}" 2>/dev/null | cut -f1 || true)"
    if [[ -z "${AEGIS_ROS_REV}" ]]; then
        echo ">>> Could not resolve '${AEGIS_ROS_TAG}' on the remote, disabling layer cache."
        AEGIS_ROS_REV="$(date +%s)"
    fi

    BUILD_CMD=(podman build "${SCRIPT_DIR}"
        --file "${CONTAINERFILE}"
        --build-arg "BASE_REF=${BASE_IMAGE}:${IMAGE_VERSION}"
        --build-arg "AEGIS_ROS_TAG=${AEGIS_ROS_TAG}"
        --build-arg "AEGIS_ROS_REV=${AEGIS_ROS_REV}"
        -t "${PROD_REF}")
    ((FORCE_BUILD)) && BUILD_CMD+=(--no-cache)

    echo ">>> Building ${PROD_REF} (${AEGIS_ROS_TAG} @ ${AEGIS_ROS_REV:0:8})..."
    "${BUILD_CMD[@]}"
    echo ">>> Built ${PROD_REF}"
fi

# --- Push ------------------------------------------------------------------

if ((DO_PUSH)); then
    podman image exists "${PROD_REF}" || {
        echo "Error: ${PROD_REF} does not exist locally, nothing to push." >&2
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

if ((DO_RUN == 0)); then
    exit 0
fi

# --- Run -------------------------------------------------------------------

if podman container exists "${CONTAINER_NAME}"; then
    echo "Error: container '${CONTAINER_NAME}' already exists." >&2
    echo "       podman rm -f ${CONTAINER_NAME}   (or pass --name)" >&2
    exit 1
fi

RUN_CMD=(podman run --rm --interactive --tty
    --name "${CONTAINER_NAME}"
    # ROS 2 discovery and real hardware (Basler GigE, robot controller)
    --network host
    --ipc host
    --env "ROS_DOMAIN_ID=${ROS_DOMAIN_ID:-0}")

if ((WITH_GUI)); then
    if [[ -z "${DISPLAY:-}" ]]; then
        echo ">>> DISPLAY is not set; RViz will not be able to open a window."
    fi
    RUN_CMD+=(--env "DISPLAY=${DISPLAY:-}"
        --env QT_X11_NO_MITSHM=1
        --volume /tmp/.X11-unix:/tmp/.X11-unix:ro
        # Required for X11 sockets and device nodes under SELinux
        --security-opt label=disable)
    [[ -d /dev/dri ]] && RUN_CMD+=(--device /dev/dri)
else
    # Do not start RViz if there is nowhere to draw it
    if ! printf '%s\n' "${LAUNCH_ARGS[@]:-}" | grep -q '^launch_rviz:='; then
        LAUNCH_ARGS+=("launch_rviz:=false")
    fi
fi

# DepthAI cameras enumerate over USB
[[ -d /dev/bus/usb ]] && RUN_CMD+=(--volume /dev/bus/usb:/dev/bus/usb)

RUN_CMD+=("${PROD_REF}" "${LAUNCH_ARGS[@]:-}")

if ((DRY_RUN)); then
    printf '%q ' "${RUN_CMD[@]}"
    echo
    exit 0
fi

echo ">>> Running ${PROD_REF} as ${CONTAINER_NAME}"
exec "${RUN_CMD[@]}"
