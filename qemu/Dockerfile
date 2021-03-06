## base image
FROM ubuntu:16.04

MAINTAINER Yuya Isaka

## Install build-essentials and qemu
## build-essential ... compile environment
## qemu ... run environment
RUN apt-get update
RUN apt-get install -y --no-install-recommends build-essential qemu-system

## Copy source to the workdir
COPY src /usr/src
WORKDIR /usr/src
## compile -> advos.img
RUN make 

## Run the OS with qemu
## OS image (advos.img) RUN
CMD ["qemu-system-x86_64", "-m", "1024", \
	"-drive", "id=disk,file=advos.img,if=none", \
	"-device", "ahci,id=ahci", \
	"-device", "ide-drive,drive=disk,bus=ahci.0", \
	"-boot", "a", "-display", "curses"]
