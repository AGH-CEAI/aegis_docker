#!/bin/bash
set -e

source "/opt/ros/${ROS_DISTRO}/setup.bash"
source /ws/install/setup.bash

# Escape hatch for debugging: `podman run ... aegis_prod shell`
if [[ "${1:-}" == "shell" ]]; then
    shift
    exec "${@:-/bin/bash}"
fi

exec ros2 launch aegis_bringup bringup.launch.py "$@"
