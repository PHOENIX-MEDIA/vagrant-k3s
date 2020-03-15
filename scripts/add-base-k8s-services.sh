#!/usr/bin/env bash

### Setup cluster access @see https://rancher.com/docs/k3s/latest/en/cluster-access/
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
grep -q KUBECONFIG /home/vagrant/.profile || echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> /home/vagrant/.profile

### Install Helm
curl -sfL -o /tmp/helm.tar.gz https://get.helm.sh/helm-v3.1.2-linux-amd64.tar.gz
sudo tar -C /usr/bin -xzf /tmp/helm.tar.gz --strip-components=1 linux-amd64/helm
rm /tmp/helm.tar.gz

### Add K8S dashboard
GITHUB_URL=https://github.com/kubernetes/dashboard/releases
VERSION_KUBE_DASHBOARD=$(curl -w '%{url_effective}' -I -L -s -S ${GITHUB_URL}/latest -o /dev/null | sed -e 's|.*/||')
kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/${VERSION_KUBE_DASHBOARD}/aio/deploy/recommended.yaml
