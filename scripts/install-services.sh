#!/usr/bin/env bash
set -e
set -x

###########################################
##### This should to be run as root #######
###########################################

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Prepare package manager"
apt-get install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common git ssl-cert
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"

echo "Install docker"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

echo "Enable ( unsecure ) docker remote access and add vagrant user to docker group to allow usage"
usermod -a -G docker vagrant
sed -i 's#ExecStart=/usr/bin/dockerd#ExecStart=/usr/bin/dockerd -H unix:///var/run/docker.sock -H tcp://0.0.0.0:2375#' /lib/systemd/system/docker.service
systemctl daemon-reload
systemctl restart docker

echo "We need legacyiptables in Debian 10 for DNS and stuff to work"
update-alternatives --set iptables /usr/sbin/iptables-legacy

echo "Install k3s"
curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE="600" INSTALL_K3S_EXEC="server --no-deploy traefik --no-deploy servicelb --docker" INSTALL_K3S_VERSION="v1.19.14+k3s1" sh -s -

sleep 30s
kubectl get nodes

echo "Setup cluster access @see https://rancher.com/docs/k3s/latest/en/cluster-access/"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
grep -q KUBECONFIG /root/.profile || echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> /root/.profile
chown vagrant:vagrant /etc/rancher/k3s/k3s.yaml

echo "Install Helm"
curl -sfL -o /tmp/helm.tar.gz https://get.helm.sh/helm-v3.5.4-linux-amd64.tar.gz
tar -C /usr/bin -xzf /tmp/helm.tar.gz --strip-components=1 linux-amd64/helm
rm /tmp/helm.tar.gz

### Add the helm repos
helm repo add stable https://charts.helm.sh/stable
helm repo add jetstack https://charts.jetstack.io
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update

echo "Install nginx ingress without load balancer by using host port binds"
helm install nginx stable/nginx-ingress --namespace kube-system --set rbac.create=true,controller.hostNetwork=true,controller.dnsPolicy=ClusterFirstWithHostNet,controller.kind=DaemonSet

echo "Add K8S dashboard"
GITHUB_URL=https://github.com/kubernetes/dashboard/releases
VERSION_KUBE_DASHBOARD=$(curl -w '%{url_effective}' -I -L -s -S ${GITHUB_URL}/latest -o /dev/null | sed -e 's|.*/||')
kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/${VERSION_KUBE_DASHBOARD}/aio/deploy/recommended.yaml

echo "We don't need specific auth locally so we set rbac to cluster admin"
cat <<EOF | kubectl delete -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kubernetes-dashboard
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kubernetes-dashboard
subjects:
  - kind: ServiceAccount
    name: kubernetes-dashboard
    namespace: kubernetes-dashboard
EOF

cat <<EOF | kubectl create -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kubernetes-dashboard
  namespace: kubernetes-dashboard
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: kubernetes-dashboard
    namespace: kubernetes-dashboard
EOF

echo "Patch the default deployment to skip auth and give the system some time"
kubectl patch deploy --namespace kubernetes-dashboard kubernetes-dashboard --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--enable-skip-login"}]'
sleep 10s


echo "--------------- INSTALL RANCHER ---------------"

echo "Create Namespaces"
kubectl create namespace cert-manager
kubectl create namespace cattle-system


echo "Deploy Cert-Manager"
helm install cert-manager jetstack/cert-manager --namespace cert-manager --version v1.2.0 --create-namespace --set installCRDs=true --wait --timeout 20m

echo "Deploy Rancher"
helm install rancher rancher-stable/rancher --namespace cattle-system --set hostname=rancher.local-project.test --wait --timeout 20m

sleep 2m

kubectl delete node debian-10
sleep 2m