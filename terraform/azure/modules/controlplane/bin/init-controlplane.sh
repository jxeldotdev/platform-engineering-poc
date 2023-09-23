#!/bin/bash

# Taken from github.com/scholzj/terraform-aws-kubernetes and modified to fit my needs.\
exec &> /var/log/init-azure-kubernetes-master.log

set -o verbose
set -o errexit
set -o pipefail

export KUBEADM_TOKEN="${kubeadm_token}"
export CLUSTER_NAME="${cluster_name}"
export AZ_SUBSCRIPTION_ID="${subscription_id}"
export AZ_RG_NAME="${rg_name}"
export ADDONS="${addons}"
export APISERVER_NLB="${apiserver_nlb}"
export CONTAINER_NAME="${container_name}"
export AZ_BLOB_STORAGE_ACCOUNT="${storage_account_name}"
export KUBERNETES_VERSION="1.26.2"
export AZ_STORAGE_KEY="${az_storage_key}"



# Set this only after setting the defaults
set -o nounset

sudo dnf install -y jq

sudo systemctl enable firewalld --now
firewall-cmd --add-port 22/tcp --add-port 6443/tcp --add-port 2379-2380/tcp --add-port 10250-10252/tcp --permanent --zone=public

sudo systemctl restart firewalld


IS_FIRST_MASTER=false

HOST=$(hostname)
if [ $HOST == "k8s-controlplane000000" ] ; then IS_FIRST_MASTER=true; fi

# We needed to match the hostname expected by kubeadm and the hostname used by kubelet
METADATA="$(curl -s -H Metadata:true curl http://169.254.169.254/metadata/instance?api-version=2021-02-01)"
LOCAL_IP_ADDRESS=$(echo $METADATA | jq -r '.network.interface[].ipv4.ipAddress[].privateIpAddress')
FQDN="$(echo $METADATA | jq -r '.compute.name')"
DNS_NAME=$(echo "$FQDN" | tr 'A-Z' 'a-z')

install_deps() {
  # Install Azure CLI, Disable SELinux, Configure Kernel Modules

  # Azure CLI
  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  sudo dnf install -y https://packages.microsoft.com/config/rhel/9.0/packages-microsoft-prod.rpm
  sudo dnf install azure-cli -y

  # SELINUX - setenforce returns non zero if already SE Linux is already disabled
  is_enforced=$(getenforce)
  if [[ $is_enforced != "Disabled" ]]; then
    sudo setenforce 0
    sudo sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
  fi

  # Enable required kernel modules for containerd
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

  sudo modprobe overlay
  sudo modprobe br_netfilter

  # Setup required sysctl params, these persist across reboots.
  cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

  # Apply sysctl params without reboot
  sudo sysctl --system
}
install_components() {
  sudo dnf install -y curl gettext device-mapper-persistent-data lvm2 iproute-tc
  OS=CentOS_8_Stream
  VERSION=1.26
  curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/devel:kubic:libcontainers:stable.repo
  curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$VERSION/$OS/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo
  dnf install cri-o -y
  systemctl daemon-reload
  systemctl enable --now crio
  systemctl status crio

  # Install Kubernetes
  sudo cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

  dnf makecache
  dnf install -y kubelet-$KUBERNETES_VERSION kubeadm-$KUBERNETES_VERSION --disableexcludes=kubernetes

  systemctl enable kubelet

  # Fix certificates file on CentOS
  if cat /etc/*release | grep Alma; then
      rm -rf /etc/ssl/certs/ca-certificates.crt/
      cp /etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt
  fi
}

init_cluster() {
  # Initialize the master node
  sudo kubeadm reset --force
  sudo kubeadm config images pull
  sudo kubeadm init --token $KUBEADM_TOKEN --control-plane-endpoint $APISERVER_NLB --upload-certs | sudo tee /var/log/kubeadm-init-master.log

  # Login + Download script to copy certificate files to key vault.
  echo "LOGGING INTO AZURE"
  az login --identity
  # echo "DOWNLOADING SCRIPT TO COPY CERTS"
  # az storage blob download --file "/tmp/copy_certs_to_key_vault.py" --name "copy_certs_to_key_vault.py" --container-name $CONTAINER_NAME --account-name $AZ_BLOB_STORAGE_ACCOUNT


  # Install deps + run scripts
  python3.9 -m pip install azure-keyvault-certificates azure-identity azure-keyvault-secrets pyopenssl
  echo "Copying certs to Key Vault"
  # python3.9 ./tmp/copy_certs_to_key_vault.py

  # Then how would we get the join command?
  MASTER_JOIN_CMD=$(grep '\-\-certificate-key' -B 2 /var/log/kubeadm-init-master.log | tr -d '\n' | tr -d '\')
  WORKER_JOIN_CMD=$(grep '\-\-discovery-token' -B 1 /var/log/kubeadm-init-master.log | tail -n 2 | tr -d '\n' | tr -d '\')
  
  echo "Calculated the following join commands:"
  echo "MASTER: $MASTER_JOIN_CMD"
  echo "WORKER: $WORKER_JOIN_CMD"
  
  # Need to write that to storage blob for other master nodes to read
  echo $MASTER_JOIN_CMD > /tmp/master-join-command.sh
  echo $WORKER_JOIN_CMD > /tmp/worker-join-command.sh

  echo "UPLOADING TO AZURE STORAGE BLOB"
  az storage blob upload -f /tmp/master-join-command.sh -c $CONTAINER_NAME --account-name $AZ_BLOB_STORAGE_ACCOUNT
  az storage blob upload -f /tmp/worker-join-command.sh -c $CONTAINER_NAME --account-name $AZ_BLOB_STORAGE_ACCOUNT

  # Use the local kubectl config for further kubectl operations
  export KUBECONFIG=/etc/kubernetes/admin.conf

  # Install calico
  kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/tigera-operator.yaml
  kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/custom-resources.yaml
}

download_cert() {
    cert_name=$1
    file_path=$2
    cert_type=$3
    case $cert_type in
        "x509")
            az keyvault secret download --vault-name ${vault_name} -n $cert_name -f /tmp/$cert_name.pfx 
            openssl pkcs12 -in /tmp/$cert_name.pfx -nocerts -out $cert_path.key
            openssl pkcs12 -in /tmp/$cert_name.pfx -clcerts -nokeys -out $cert_path.crt
            rm /tmp/$cert_name.pfx
            ;;
        "rsa")
            az keyvault secret download --vault-name ${vault_name} -n $cert_name -f $file_path.key
            openssl rsa -in $file_path.key -pubout > $file_path.pub
            ;;
        *)
            echo "Unknown certificate type: $cert_type"
            exit 1
            ;;
    esac
}

join_cluster() {
  sudo kubeadm reset --force
  sudo kubeadm config images pull
  
  az login --identity
  # c=0
  # FILE_EXISTS=false
  # while [ $FILE_EXISTS == false ]; do
  #   if ! az storage blob exists -f master-join-command.sh --container-name $CONTAINER_NAME --account-name $AZ_BLOB_STORAGE_ACCOUNT; then
  #     if [$c > 30]; then
  #       echo "FAILURE: Unable to grab join command file"
  #       break
  #     fi
  #     ((c+=1))
  #     echo "Join script still not available, retrying in 10s. "
  #     sleep 10
  #   else
  #     echo "File exists, continuing"
  #     FILE_EXISTS=true
  #   fi
  # done

  # certs_to_import=("$${CLUSTER_NAME}-ca;/etc/kubernetes/pki/ca;x509" "$${CLUSTER_NAME}-sa;/etc/kubernetes/pki/sa;rsa" "$${CLUSTER_NAME}-front-proxy-ca;/etc/kubernetes/pki/front-proxy-ca;x509" "$${CLUSTER_NAME}-etcd;/etc/kubernetes/pki/etcd/ca;x509")
  # for cert in "$${certs_to_import[@]}"; do
  #     cert_name=$(echo $cert | cut -f 1 -d ';')
  #     cert_path=$(echo $cert | cut -f 2 -d ';')
  #     cert_type=$(echo $cert | cut -f 3 -d ';')
  #     download_cert $cert_name $cert_path $cert_type
  # done
  
  az storage blob download -f /tmp/master-join-command.sh --container-name $CONTAINER_NAME --account-name $AZ_BLOB_STORAGE_ACCOUNT
  chmod +x /tmp/master-join-command.sh
  /tmp/master-join-command.sh | tee /var/log/init-join-cluster.log
  # sudo kubeadm join $APISERVER_NLB --token $KUBEADM_TOKEN --control-plane --discovery-token-unsafe-skip-ca-verification

}
create_user() {
  # Allow the user to administer the cluster
  kubectl create clusterrolebinding admin-cluster-binding --clusterrole=cluster-admin --user=admin

  # Prepare the kubectl config file for download to client (IP address)
  export KUBECONFIG_OUTPUT=/home/jfreeman/kubeconfig_ip
  kubeadm kubeconfig user --client-name admin --config /tmp/kubeadm.yaml > $KUBECONFIG_OUTPUT
  chown centos:centos $KUBECONFIG_OUTPUT
  chmod 0600 $KUBECONFIG_OUTPUT

  cp /home/jfreeman/kubeconfig_ip /home/jfreeman/kubeconfig
  sed -i "s/server: https:\/\/.*:6443/server: https:\/\/$LOCAL_IP_ADDRESS:6443/g" /home/jfreeman/kubeconfig_ip
  sed -i "s/server: https:\/\/.*:6443/server: https:\/\/$DNS_NAME:6443/g" /home/jfreeman/kubeconfig
  chown centos:centos /home/jfreeman/kubeconfig
  chmod 0600 /home/jfreeman/kubeconfig
}

join_or_init() {
  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  sudo dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm
  sudo dnf install azure-cli -y
  az login --identity
  vms=$(az vmss list-instances -n k8s-controlplane -g k8s | jq '.[].osProfile.computerName' -r | tr '\n' ' ')
  # last 2 numbers in hostname
  short_vms=($(for vm in $vms; do echo $vm | sed 's/.*\(..\)/\1/'; done))
  short_hostname=$(hostname | sed 's/.*\(..\)/\1/')
  
  # cbf sorting the list in bash, lets assume it'll be sorted by azure api
  if [[ $short_hostname == $${short_vms[0]} ]] ; then
    init_cluster
    create_user
  else
    join_cluster
  fi
}


install_deps
install_components
join_or_init

# install_addons
