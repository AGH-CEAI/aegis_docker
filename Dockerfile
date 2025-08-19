ARG ROS_DISTRO=humble
ARG PPA_HOSTNAME=geonosis

FROM docker.io/osrf/ros:${ROS_DISTRO}-desktop
ARG ROS_DISTRO
ARG PPA_HOSTNAME

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

# Local PPA for Basler proprietary packages
RUN echo "deb [trusted=yes] http://${PPA_HOSTNAME}/debian ./" | tee -a /etc/apt/sources.list > /dev/null \
    && apt update  \
    && apt install -y \
        libxcb-cursor-dev \
    && apt install -y \
        codemeter \
        pylon \
        pylon-supplementary-package-for-blaze \
    && export SUDO_FORCE_REMOVE=yes \
    && apt autoremove -y \
    && apt clean \
    && rm -rf /var/lib/apt/lists/*

CMD ["/bin/bash"]
