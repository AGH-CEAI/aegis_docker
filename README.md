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
Build and tag all 3 stages or build whole stack at once:
```bash
podman build . -t ceai/aegis_dev:latest
# OR
./build.sh

```
then proceed to toolbox creation:

```bash
toolbox create --image localhost/ceai/aegis_dev:latest
# Check available images
toolbox list
```

**Entering into a new terminal**:
```bash
toolbox enter aegis_dev-latest
```

#### Forwarding the X-session
Podman does almost everthing, there could be a problem with the magic cookie:
```bash
# 1. Check the MIT cookie for unix:10
xauth list
# 2. Duplicate the cookie for the toolbox
xauth add toolbx/unix:10 MIT-MAGIC-COOKIE-1 <PASTE_HERE>
# 3. You can now access the toolbx's X-session on a remote machine
ssh -X remote-host
```
