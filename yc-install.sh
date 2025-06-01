#!/bin/sh

yc vpc network create --name otus-net --description "otus-net" && \
yc vpc subnet create --name otus-subnet --range 192.168.0.0/24 --network-name otus-net --description "otus-subnet" && \
yc compute instance create \
  --name otus-vm \
  --hostname otus-vm \
  --cores 2 \
  --memory 4 \
  --create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts-oslogin \
  --network-interface subnet-name=otus-subnet,nat-ip-version=ipv4 \
  --metadata-from-file user-data=cloud-init.yaml