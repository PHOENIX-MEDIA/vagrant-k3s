#!/usr/bin/env bash

### Prepare package manager
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"

### Install docker
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

### Enable ( unsecure ) docker remote access
sudo sed -i 's#ExecStart=/usr/bin/dockerd#ExecStart=/usr/bin/dockerd -H unix:///var/run/docker.sock -H tcp://0.0.0.0:2375#' /lib/systemd/system/docker.service
sudo systemctl daemon-reload
sudo systemctl restart docker