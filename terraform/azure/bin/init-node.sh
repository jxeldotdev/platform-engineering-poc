#!/bin/bash

exec &> /var/log/init-aws-kubernetes-node.log

set -o verbose
set -o errexit
set -o pipefail

export KUBEADM_TOKEN=${kubeadm_token}
export APISERVER_NLB=${apiserver_nlb}
export DNS_NAME=${dns_name}
export KUBERNETES_VERSION="1.26.2"

export CLUSTER_NAME=${cluster_name}
export ASG_NAME=${asg_name}
export ASG_MIN_NODES="${asg_min_nodes}"
export ASG_MAX_NODES="${asg_max_nodes}"
export AZ_REGION=${az_region}
export AZ_SUBNETS="${az_subnets}"
export AZ_SUBSCRIPTION_ID="${subscription_id}"
export AZ_RG_NAME="${rg_name}"
export ADDONS="${addons}"
export KUBERNETES_VERSION="1.26.2"

# Set this only after setting the defaults
set -o nounset

# We to match the hostname expected by kubeadm an the hostname used by kubelet
LOCAL_IP_ADDRESS=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
FULL_HOSTNAME="$(curl -s http://169.254.169.254/latest/meta-data/hostname)"

# Make DNS lowercase
DNS_NAME=$(echo "$DNS_NAME" | tr 'A-Z' 'a-z')


install_deps() {
  # Install Azure CLI, Disable SELinux, Configure Kernel Modules

  # Azure CLI
  rpm --import https://packages.microsoft.com/keys/microsoft.asc
  dnf install -y https://packages.microsoft.com/config/rhel/9.0/packages-microsoft-prod.rpm
  dnf install azure-cli

  # SELINUX - setenforce returns non zero if already SE Linux is already disabled
  is_enforced=$(getenforce)
  if [[ $is_enforced != "Disabled" ]]; then
    setenforce 0
    sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
  fi

  # Enable required kernel modules for containerd
  cat <<EOF | tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

  modprobe overlay
  modprobe br_netfilter

  # Setup required sysctl params, these persist across reboots.
  cat <<EOF | tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

  # Apply sysctl params without reboot
  sysctl --system
}

install_components() {
  sudo dnf install -y curl gettext device-mapper-persistent-data lvm2
  sudo dnf-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  sudo dnf install -y containerd.io
  mkdir -p /etc/containerd
  containerd config default > /etc/containerd/config.toml
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
  systemctl restart containerd
  systemctl enable containerd

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

  dnf install -y kubelet-$KUBERNETES_VERSION kubeadm-$KUBERNETES_VERSION kubernetes-cni --disableexcludes=kubernetes

  systemctl enable kubelet
  systemctl start kubelet

  # Fix certificates file on CentOS
  if cat /etc/*release | grep ^NAME= | grep CentOS ; then
      rm -rf /etc/ssl/certs/ca-certificates.crt/
      cp /etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt
  fi
}

join_cluster() {
  cat >./kubeadm.yaml <<EOF
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: JoinConfiguration
discovery:
  bootstrapToken:
    apiServerEndpoint: $APISERVER_NLB:443
    token: $KUBEADM_TOKEN
    unsafeSkipCAVerification: true
  timeout: 5m0s
  tlsBootstrapToken: $KUBEADM_TOKEN
nodeRegistration:
  kubeletExtraArgs:
    cloud-provider: azure
    read-only-port: "10255"
    cgroup-driver: systemd
  name: $FULL_HOSTNAME
---
EOF

  kubeadm reset --force
  kubeadm join --config /tmp/kubeadm.yaml

}
