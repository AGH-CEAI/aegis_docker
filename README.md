# aegis_docker

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit)](https://github.com/pre-commit/pre-commit)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.17018797.svg)](https://doi.org/10.5281/zenodo.17018797)

This package contains all files for building & run container images for the Aegis robot station.

The requirements for the packages are directly taken from the [aegis_ros](https://github.com/AGH-CEAI/aegis_ros).

## Main container image

To build a base image, both for `production` and `development`, run the following script and follow the instructions:
```bash
./build_image.sh
```

## Production container

## Development toolbx container
Currently there is no docker compose for running it - please stick to the toolbox approach.

### Toolbox
Toolbox ([toolbx](https://containertoolbx.org/)) is a development tool to mitigate the headaches about the users' privileges.

To enable GPU support in toolbx containers on Ubuntu 22/24 host [some manual updates](./docs/ubuntu_gpu_toolbx.md) are necessary.

**(Automatic) Setup**
Add the following script to your PATH. Run it and follow the instructions:
```bash
mkdir -p ~/.local/bin
ln -s ~/ceai_ws/src/aegis_docker/enter_toolbx.sh ~/.local/bin/aegis-toolbx
ln -s ~/ceai_ws/src/aegis_docker/enter_toolbx.sh ~/.local/bin/cleanup-aegis-toolbx

# Enter/recreate/remove toolbx. Best called in the working aegis_ros directory to detect the branch.
aegis-toolbx
# Cleanup all aegis toolbxes
cleanup-aegis-toolbx
```
These scripts handles all creation and cleanup of the development toolbxes.

> [NOTE]
> Double check your $PATH env variable, it should contain the `~/.local/bin` directory.


**(Manual) Building**:
```bash
podman build . -t ceai/aegis_dev:latest
toolbox create --image localhost/ceai/aegis_dev:latest
# Check available images
toolbox list
```

**(Manual) Entering into a new terminal**:
```bash
toolbox enter aegis_dev-latest
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
