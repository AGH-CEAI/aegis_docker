ARG ROS_DISTRO=humble

FROM docker.io/osrf/ros:${ROS_DISTRO}-desktop

WORKDIR /ws

RUN apt update  \
    && apt install -y \
        clang \
        zsh \
        ros-dev-tools \
        ros-${ROS_DISTRO}-depthai-ros \
        ros-${ROS_DISTRO}-ros2-control \
        ros-${ROS_DISTRO}-ros2-controllers \
    # Setup workspace
    && git clone -b ${ROS_DISTRO}-devel https://github.com/AGH-CEAI/aegis_ros.git src/aegis_ros \
    && vcs import src < src/aegis_ros/aegis/aegis.repos \
    # Install dependencies
    && rosdep update --rosdistro $ROS_DISTRO \
    && rosdep install --from-paths src -y -i \
    # Size optimalization
    && export SUDO_FORCE_REMOVE=yes \
    && apt autoremove -y \
    && apt clean \
    && rm -rf /var/lib/apt/lists/*

CMD ["/bin/bash"]
