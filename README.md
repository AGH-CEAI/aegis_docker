# aegis_docker

This package contains all files for building & run container images for the Aegis robot station.

The requirements for the packages are directly taken from the [aegis_ros](https://github.com/AGH-CEAI/aegis_ros).

## Development container image

### Docker
You can build the image using the following command:
```bash
docker build . -t ceai/aegis_dev:latest
```
Currently there is no docker compose for running it - please stick to the toolbox approach.

### Toolbox
Toolbox ([toolbx](https://containertoolbx.org/)) is a development tool to mitigate the headaches about the users' privileges.

To enable GPU support in toolbx containers on Ubuntu 22/24 host [some manual updates](./docs/ubuntu_gpu_toolbx.md) are necessary.

**Building**:
```bash
podman build . -t ceai/aegis_dev:latest
toolbox create --image localhost/ceai/aegis_dev:latest
# Check available images
toolbox list
```

**Entering into a new terminal**:
```bash
toolbox enter aegis_dev-latest
```

---

### Private Packages Repo (PPA)

How to Set up private repo [here](./utils/aegis_packages/README.md).

**Adding private repo**
```bash
echo "deb [trusted=yes] http://192.168.0.100/debian ./" | tee -a /etc/apt/sources.list > /dev/null
```
### Containers registry

[Instructions how to use self-hosted container registry.](./utils/containers_registry/README.md)

#### Building & pushing a particular release tag
```bash
export REGISTRY_HOSTNAME=geonosis:5000
export AEGIS_ROS_VERSION=<TAG>
export AEGIS_CONTAINER_VERSION=<TAG>

# if the building is happening on the same machine as PPA server, add argument:
# --add-host $(hostname):$(hostname -I | awk '{print $1}')
podman build . -t ceai/aegis_dev:${AEGIS_CONTAINER_VERSION} --build-arg AEGIS_ROS_TAG=${AEGIS_ROS_VERSION}
podman tag ceai/aegis_dev:${AEGIS_CONTAINER_VERSION} ${REGISTRY_HOSTNAME}/ceai/aegis:${AEGIS_CONTAINER_VERSION}
podman push ${REGISTRY_HOSTNAME}/ceai/aegis:${AEGIS_CONTAINER_VERSION}
```

#### Pulling & entering a particular release tag
```bash
export REGISTRY_HOSTNAME=geonosis:5000
export AEGIS_CONTAINER_VERSION=<TAG>

podman pull ${REGISTRY_HOSTNAME}/ceai/aegis:${AEGIS_CONTAINER_VERSION}

toolbox create --image ${REGISTRY_HOSTNAME}/ceai/aegis:${AEGIS_CONTAINER_VERSION}
toolbox enter aegis-${AEGIS_CONTAINER_VERSION}
```

---

### Known issues:

##### `sudo`: unable to resolve host `toolbox` / `toolbx`

- (Host) Add toolbox to the `/etc/hosts`:

```
# sudo nano /etc/hosts
127.0.0.1        toolbox
127.0.0.1        toolbx
```

##### user is not in the sudoers file

- (Host) Install [crun (1.8-1)](https://launchpad.net/ubuntu/lunar/amd64/crun/1.8-1) :
```bash
wget http://launchpadlibrarian.net/650575198/crun_1.8-1_amd64.deb
sudo apt install ./crun_1.8-1_amd64.deb
rm ./crun_1.8-1_amd64.deb
```
- (Toolbox) create group:
```bash
newgrp sudo
```
- [Source](https://github.com/containers/toolbox/issues/1361)
