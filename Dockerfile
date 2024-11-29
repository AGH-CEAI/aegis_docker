ARG ROS_DISTRO=humble

FROM ros:${ROS_DISTRO}

WORKDIR /ws

RUN apt-get update && \
    apt-get install -y \
        zsh \
        ros-dev-tools && \
    # Setup workspace
    git clone -b init_version https://github.com/AGH-CEAI/aegis_ros.git src/aegis_ros && \
    vcs import src < src/aegis_ros/aegis/aegis.repos && \
    # Install dependencies
    # rosdep init && \
    rosdep update --rosdistro $ROS_DISTRO && \
    rosdep install --from-paths src -y -i && \
    # Size optimalization
    export SUDO_FORCE_REMOVE=yes && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

CMD ["/bin/bash"]