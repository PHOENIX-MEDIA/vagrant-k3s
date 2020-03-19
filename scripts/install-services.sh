#!/usr/bin/env bash
set -e
set -x

###########################################
##### This should to be run as root #######
###########################################

DIR="$(cd "$(dirname "$0")" && pwd)"

### Prepare package manager
apt-get install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common git ssl-cert
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"

### Install docker
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

### Enable ( unsecure ) docker remote access
sed -i 's#ExecStart=/usr/bin/dockerd#ExecStart=/usr/bin/dockerd -H unix:///var/run/docker.sock -H tcp://0.0.0.0:2375#' /lib/systemd/system/docker.service
systemctl daemon-reload
systemctl restart docker

### Install k3s
K3S_KUBECONFIG_MODE="666" INSTALL_K3S_EXEC="server --no-deploy traefik --no-deploy servicelb --flannel-iface eth1 --docker" /tmp/get-k3s-io.sh

sleep 30s
kubectl get nodes

### Setup cluster access @see https://rancher.com/docs/k3s/latest/en/cluster-access/
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
grep -q KUBECONFIG /root/.profile || echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> /root/.profile

### Install Helm
curl -sfL -o /tmp/helm.tar.gz https://get.helm.sh/helm-v3.1.2-linux-amd64.tar.gz
tar -C /usr/bin -xzf /tmp/helm.tar.gz --strip-components=1 linux-amd64/helm
rm /tmp/helm.tar.gz

helm repo add stable https://kubernetes-charts.storage.googleapis.com/
helm repo update

### Install nginx ingress without load balancer by using host port binds
helm install nginx stable/nginx-ingress --namespace kube-system --set rbac.create=true,controller.hostNetwork=true,controller.dnsPolicy=ClusterFirstWithHostNet,controller.kind=DaemonSet

### Add K8S dashboard
GITHUB_URL=https://github.com/kubernetes/dashboard/releases
VERSION_KUBE_DASHBOARD=$(curl -w '%{url_effective}' -I -L -s -S ${GITHUB_URL}/latest -o /dev/null | sed -e 's|.*/||')
kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/${VERSION_KUBE_DASHBOARD}/aio/deploy/recommended.yaml