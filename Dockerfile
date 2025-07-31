ARG ROS_DISTRO=humble
ARG GENESIS_VER="0.2.1"

# --------------------------------------------------------------------------- #
FROM docker.io/osrf/ros:${ROS_DISTRO}-desktop as base
WORKDIR /ws

RUN apt update \
    && apt install -y \
        zsh \
        ros-dev-tools \
    # Setup workspace
    && git clone -b humble-devel https://github.com/AGH-CEAI/aegis_ros.git src/aegis_ros \
    && vcs import src < src/aegis_ros/aegis/aegis.repos \
    # Install dependencies
    && rosdep update --rosdistro ${ROS_DISTRO} \
    && rosdep install --from-paths src -y -i \
    # Size optimalization
    && export SUDO_FORCE_REMOVE=yes \
    && apt autoremove -y \
    && apt clean \
    && rm -rf /var/lib/apt/lists/*

CMD ["/bin/bash"]

# --------------------------------------------------------------------------- #
FROM base as learning
WORKDIR /ws

RUN apt update \
    && apt install -y \
        python3-pip \
    && export SUDO_FORCE_REMOVE=yes \
    && apt autoremove -y \
    && apt clean \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install \
        torch==2.7.1+cu128 \
	torchvision==2.7.1+cu128 \
	torchaudio==0.22.1+cu128 \
	--index-url https://download.pytorch.org/whl/cu128

# --------------------------------------------------------------------------- #
FROM learning AS genesis-sim
ARG GENESIS_VER
WORKDIR /ws

RUN pip3 install genesis-world==${GENESIS_VER}
