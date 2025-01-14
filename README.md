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

**Building**:
```bash
podman build . -t ceai/aegis_dev:latest
toolbox create --image localhost/ceai/aegis_dev:latest
# Check avaiable images
toolbox list
```

**Entering into a new terminal**:
```bash
toolbox enter aegis_dev-latest
```
