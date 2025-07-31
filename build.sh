#!/bin/bash

podman build . --target base -t ceai/aegis_dev:base
podman build . --target learning -t ceai/aegis_dev:learning
podman build . --target genesis-sim -t ceai/aegis_dev:genesis-sim
podman build . -t ceai/aegis_dev:latest

