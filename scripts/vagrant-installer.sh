#!/usr/bin/env bash
set -e
set -x

###########################################
##### This is the main install point ######
###########################################

sudo /home/vagrant/install-services.sh

### Setup cluster access @see https://rancher.com/docs/k3s/latest/en/cluster-access/
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
grep -q KUBECONFIG /home/vagrant/.profile || echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> /home/vagrant/.profile

### Add the main helm repo
helm repo add stable https://charts.helm.sh/stable
helm repo update

rm /home/vagrant/install-services.sh