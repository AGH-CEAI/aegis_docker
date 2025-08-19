# Private Packages Repo (PPA)

This module enables storing private *.deb packages used for automated container built.

More [here](https://linuxconfig.org/easy-way-to-create-a-debian-package-and-local-package-repository).

## Preparing packages

**Update packages list**:

Copy all *.deb packages to `./packages` directory.


**Update packages list**:
```bash
dpkg-scanpackages . | gzip -c9  > Packages.gz
```
or
```bash
sudo sh -c 'dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz'
```

## Running Server

**Docker Compose**:
```bash
docker compose up -d
```

### Adding new packages

Follow `Preparing packages` step and the list of packages will automatically update.
