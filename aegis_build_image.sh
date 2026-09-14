#!/bin/bash
# Script generated with Claude Opus 5

set -euo pipefail

# Resolve through symlinks so the build context is the repository, not $PWD.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

IMAGE_NAME="ceai/aegis_ros"
ROS_DISTRO="humble"
BASE_IMAGE="docker.io/osrf/ros:${ROS_DISTRO}-desktop"
LOCAL_PPA_HOSTNAME=geonosis

# podman prefers Containerfile over Dockerfile; accept whichever is present.
CONTAINERFILE=""
for candidate in "${SCRIPT_DIR}/Containerfile" "${SCRIPT_DIR}/Dockerfile"; do
    if [[ -f "${candidate}" ]]; then
        CONTAINERFILE="${candidate}"
        break
    fi
done

if [[ -z "${CONTAINERFILE}" ]]; then
    echo ">>> Error: no Containerfile or Dockerfile in ${SCRIPT_DIR}." >&2
    exit 1
fi

# --- Build arguments -------------------------------------------------------

echo ">>> BUILDING THE ${IMAGE_NAME} container image"
echo ">>> Using ${CONTAINERFILE}"

read -r -p ">>> Pull base image ${BASE_IMAGE} first? (Y/n): " DO_PULL
case "${DO_PULL}" in
    [nN] | [nN][oO])
        echo ">>> Skipping base image pull."
        ;;
    *)
        echo ">>> Pulling ${BASE_IMAGE}..."
        podman pull "${BASE_IMAGE}"
        ;;
esac

read -r -p ">>> AEGIS_ROS_TAG (tag/branch/commit) [humble-devel]: " AEGIS_ROS_TAG
AEGIS_ROS_TAG="${AEGIS_ROS_TAG:-humble-devel}"

read -r -p ">>> Image version [latest]: " IMAGE_VERSION
IMAGE_VERSION="${IMAGE_VERSION:-latest}"

LOCAL_TAG="${IMAGE_NAME}:${IMAGE_VERSION}"

# --- Build -----------------------------------------------------------------

echo ">>> Building ${LOCAL_TAG} (AEGIS_ROS_TAG=${AEGIS_ROS_TAG})..."
podman build "${SCRIPT_DIR}" \
    --file "${CONTAINERFILE}" \
    --build-arg "AEGIS_ROS_TAG=${AEGIS_ROS_TAG}" \
    --build-arg "ROS_DISTRO=${ROS_DISTRO}" \
    --build-arg "PPA_HOSTNAME=${LOCAL_PPA_HOSTNAME}" \
    -t "${LOCAL_TAG}"

echo ">>> Built ${LOCAL_TAG}"

# --- Push ------------------------------------------------------------------

read -r -p ">>> Push ${LOCAL_TAG} to a registry? (y/N): " DO_PUSH
case "${DO_PUSH}" in
    [yY] | [yY][eE][sS]) ;;
    *)
        echo ">>> Skipping push."
        exit 0
        ;;
esac

read -r -p ">>> Registry host [geonosis]: " REGISTRY_HOST
REGISTRY_HOST="${REGISTRY_HOST:-geonosis}"

read -r -p ">>> Registry port [5000]: " REGISTRY_PORT
REGISTRY_PORT="${REGISTRY_PORT:-5000}"

REMOTE_TAG="${REGISTRY_HOST}:${REGISTRY_PORT}/${IMAGE_NAME}:${IMAGE_VERSION}"

echo ">>> Tagging as ${REMOTE_TAG}..."
podman tag "${LOCAL_TAG}" "${REMOTE_TAG}"

echo ">>> Pushing ${REMOTE_TAG}..."
podman push "${REMOTE_TAG}"

echo ">>> Pushed ${REMOTE_TAG}"
