#!/usr/bin/env bash
set -e
set -x

###########################################
##### This should to be run as root #######
###########################################

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Prepare package manager"
apt-get install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common git ssl-cert jq
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"

echo "Install docker"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

echo "Install ntp and socat"
apt-get install -y ntp socat

echo "Enable ( unsecure ) docker remote access and add vagrant user to docker group to allow usage"
usermod -a -G docker vagrant
sed -i 's#ExecStart=/usr/bin/dockerd#ExecStart=/usr/bin/dockerd -H unix:///var/run/docker.sock -H tcp://0.0.0.0:2375#' /lib/systemd/system/docker.service
systemctl daemon-reload
systemctl restart docker

# pull alpine and busybox to have it in the box
docker pull alpine
docker pull busybox

echo "We need legacyiptables in Debian 10 for DNS and stuff to work"
update-alternatives --set iptables /usr/sbin/iptables-legacy

echo "Add google dns server"
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

echo "Install k3s"
curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE="600" INSTALL_K3S_EXEC="server --disable traefik --disable servicelb --docker" INSTALL_K3S_VERSION="v1.25.9+k3s1" sh -s - || (journalctl -xe && exit 1)

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

helm plugin install https://github.com/chartmuseum/helm-push.git
mkdir -p /home/vagrant/.local/share
cp -a /root/.local/share/helm /home/vagrant/.local/share/
chown -R vagrant:vagrant /home/vagrant/.local/share


### Add the helm repos
helm repo add stable https://charts.helm.sh/stable
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update

echo "Install nginx ingress without load balancer by using host port binds"
helm install nginx ingress-nginx/ingress-nginx --namespace kube-system --set rbac.create=true,controller.hostNetwork=true,controller.dnsPolicy=ClusterFirstWithHostNet,controller.kind=DaemonSet,controller.ingressClass=nginx,controller.ingressClassResource.default=true

echo "--------------- INSTALL RANCHER ---------------"
echo "Create Namespaces"
kubectl create namespace cert-manager
kubectl create namespace cattle-system


echo "Deploy Cert-Manager"
helm install cert-manager jetstack/cert-manager --namespace cert-manager --version v1.11.0 --create-namespace --set installCRDs=true --wait --timeout 20m

echo "Deploy Rancher"
helm install rancher rancher-stable/rancher --version 2.7.4 --namespace cattle-system --set hostname=rancher.local-project.test --set replicas=1 --set bootstrapPassword=admin --set global.cattle.psp.enabled=false --set ingress.extraAnnotations.'kubernetes\.io/ingress\.class'=nginx  --wait --timeout 20m

echo "Pre-Configure Rancher"
echo "wait until rancher server started"
while true; do
  RANCHER_POD=$(kubectl -n cattle-system get pods -l app=rancher | grep '1/1' | head -1 | awk '{ print $1 }')
  RANCHER_POD_CMD="kubectl -n cattle-system exec ${RANCHER_POD}"
  $RANCHER_POD_CMD -- curl -sLk https://127.0.0.1/ping && break
  sleep 5
done

# Login
echo "wait until rancher is ready and create a Token"
while true; do

	LOGINRESPONSE=$($RANCHER_POD_CMD -- curl "https://127.0.0.1/v3-public/localProviders/local?action=login" -H 'content-type: application/json' --data-binary '{"username":"admin","password":"admin"}' --insecure)
	LOGINTOKEN=$(echo $LOGINRESPONSE | jq -r .token)

    if [ "$LOGINTOKEN" != "null" ]; then
        break
    else
        sleep 5
    fi
done

## change password
$RANCHER_POD_CMD -- curl -s 'https://127.0.0.1/v3/users?action=changepassword' -H 'content-type: application/json' -H "Authorization: Bearer $LOGINTOKEN" --data-binary '{"currentPassword":"admin","newPassword":"'thisisunsafe'"}' --insecure

echo "give the cluster some time, and remove curent node from the cluster, that the node is not missing when a projekt vagrant starts"
sleep 10s
kubectl delete node debian-10
sleep 30s