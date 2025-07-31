# GPU in toolbx containers for nowadays Ubuntus

## Requirements
* Installed [Nvidia Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
* Generated the [CDI specification file](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/cdi-support.html#procedure): `sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml`
* For building from source
  * `checkinstall` to encapsulate every `sudo make install` into a `*.deb` package.
  * `sudo apt install checkinstall`

## Ubuntu 22.04
* Default `podman` version is `3.4.4` - **TOO OLD** for Nvidia Container Toolkit.
* Default `toolbx`(i.e. `podman-toolbox`) is `0.0.99.2` - **TOO OLD** to support Nvidia GPU.

GPU support requires an update of `podman`, `passt`, `crun`, `podman-toolbox` and installation of `shadow-utils`.

### passt
> Download the manually pre-compiled *.deb package [here](https://dysk.agh.edu.pl/s/FjM6xDGTScpszGw) and install it
> `sudo apt-get install ./passt_20250730-1_amd64.deb`

Build a new `passt` from [source](https://passt.top/passt/about/#passt_3), version: `master` aka `a8782865c`
  * Use `sudo checkinstall make install` to install the package.

### crun
> Download the manually pre-compiled *.deb package [here](https://dysk.agh.edu.pl/s/ByQztb8qRtr5nPp) and install it
> `sudo apt-get install ./crun_1.23-1_amd64.deb`

Build a newer `crun` from [source](https://github.com/containers/crun?tab=readme-ov-file#build), version: `1.23`

### shadow-utils
> Download the manually pre-compiled *.deb package [here](https://dysk.agh.edu.pl/s/RWomFD4wXndDcrt) and install it
> `sudo apt install -o Dpkg::Options::="--force-overwrite" -f ./shadow_4.18-1_amd64.deb`

Missing library for mapping sub gids/uids rangers. Build from [source](https://github.com/shadow-maint/shadow), version: `4.18.0`

``` bash
git clone --depth 1 --branch 4.18.0 https://github.com/shadow-maint/shadow.git
cd shadow
./autogen.sh
./configure --enable-shared --enable-static --with-libsubid
make
sudo checkinstall make install
sudo ldconfig
```

### podman
> Download the manually pre-compiled *.deb package [here](https://dysk.agh.edu.pl/s/CHAEk48fFRFckTm) and install it
> `sudo apt-get install ./podman_20250730-2_amd64.deb`

Build a new `podman` from [source](https://devtodevops.com/blog/build-podman-from-source/), version: `5.5.2`
  * It requires a newer version of `golang`.
  * **WARNING**: set the `cni` and `apparmor` buildtags! (i.e. `make BUILDTAGS="cni apparmor selinux seccomp" PREFIX=/usr/local`).

Test newer `podman`:
```bash
podman --version
podman run --rm --security-opt=label=disable --device=nvidia.com/gpu=all ubuntu nvidia-smi
```

### toolbx
> Download the manually pre-compiled *.deb package [here](https://dysk.agh.edu.pl/s/45g4XGTbyzxcpFG) and install it
> `sudo apt-get install ./podman-toolbox_20250730-1_amd64.deb`

**Build** a new `podman-toolbox` from [source](https://containertoolbx.org/install/), version: `0.1.2`

1. Clone & build project from source
```bash
cd ~/repos
git clone --depth 1 --branch 0.1.2 https://github.com/containers/toolbox.git
meson setup -Dprofile_dir=/etc/profile.d builddir
meson compile -C builddir
```
2. Prepare files for `deb` package
```bash
sudo apt install -y build-essential debhelper dh-make meson ninja-build
dh_make --createorig
```
3. Edit `debian/rules` file
```
# ...
  %:
    dh $@ --buildsystem=meson
  override_dh_dwz:
    dh_dwz --exclude=toolbox
# ...
```
4. Change package name in `debian/control` file:
```
#...
Package: podman-toolbox
#...
```
5. Build and install the deb package (result will be in an upper directory)
```bash
sudo dpkg-buildpackage -rfakeroot -us -uc -b
cd ..
sudo apt install ./podman-toolbox*.deb
```

**Test** newer `toolbx`:
```bash
toolbox --version
toolbox create --image docker.io/osrf/ros:humble-desktop
toolbox enter ros-humble-desktop
# In toolbx
nvidia-smi
```

## Ubuntu 24.04
* Default `podman` version is `4.9.3` - good enough for Nvidida Container Toolkit
  *  `podman run --rm --security-optv=label=disable --device=nvidia.com/gpu=all ubuntu nvidia-smi`
* Default `toolbx`(i.e. `podman-toolbox`) is `0.0.99.3` - **TOO OLD** to support Nvidia GPU.

GPU support requires an update of `podman-toolbox` and an symbolic link to the `libsubid.so` dynamic library.

### libsubid
For unknown reason, the toolbx wants to use the `libsubid` in version `5.0.0`, but it can work with the `4.0.0` just fine.
```bash
sudo apt install -y libsubid4 libsubid-dev
sudo ln -s /usr/lib/x86_64-linux-gnu/libsubid.so.4.0.0 /usr/lib/x86_64-linux-gnu/libsubid.so.5.0.0
```

### toolbx
See the description above for the Ubuntu 22.04.
