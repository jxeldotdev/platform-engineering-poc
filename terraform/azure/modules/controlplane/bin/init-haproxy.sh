#!/bin/bash

exec &> /var/log/init-azure-haproxy.log

set -o verbose
set -o pipefail

export APPVMS="${app_vms}"
export APPVM_PORT=6443
export LBDNSNAME="${lb_dns_name}"
export LB_PORT=6443
export MASTERVM="${master_vm}"
export BACKUPVM="${backup_vm}"


setup_haproxy() {
    # Install haproxy
    apt-get install -y software-properties-common
    apt-get update -y
    apt-get install -y haproxy

    # Enable haproxy (to be started during boot)
    tmpf=$(mktemp) && mv /etc/default/haproxy $tmpf && sed -e "s/ENABLED=0/ENABLED=1/" $tmpf > /etc/default/haproxy && chmod --reference $tmpf /etc/default/haproxy

    # Setup haproxy configuration file
    HAPROXY_CFG=/etc/haproxy/haproxy.cfg
    cp -p $HAPROXY_CFG $HAPROXY_CFG.default

cat <<EOF | sudo tee $HAPROXY_CFG
global
    log 127.0.0.1   local1 notice
    log 127.0.0.1   local0 info
    chroot /var/lib/haproxy
    user haproxy
    group haproxy
    daemon
defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000
    timeout client 50000
    timeout server 50000
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http
# Listen on all IP addresses. This is required for load balancer probe to work
listen http
    bind *:$LB_PORT
    mode tcp
    option tcplog
    balance roundrobin
    maxconn 10000
EOF


    echo "ADDING IPS TO HAPROXY CONFIG"
    echo "$APPVMS"
    # Add application VMs to haproxy listener configuration
    for APPVM in $APPVMS; do  
        APPVM_IP="$(host $APPVM | awk '/has address/ { print $4 }')"
        if [[ -z $APPVM_IP ]]; then
            echo "Unknown hostname $APPVM. Cannot be added to $HAPROXY_CFG." >&2
        else
            echo "    server $APPVM $APPVM_IP:$APPVM_PORT maxconn 5000 check" >> $HAPROXY_CFG
        fi
    done

    chmod --reference "$HAPROXY_CFG.default"

    # Start haproxy service
    sudo systemctl enable --now haproxy
    sudo systemctl stop haproxy
    sudo systemctl restart haproxy
}

setup_keepalived() {
    set -x

    LB_IP=$(host $LBDNSNAME | awk '/has address/ { print $4 }')

    IS_MASTER=$( [[ $(hostname -s) == $MASTERVM ]]; echo $? )

    # keepalived uses VRRP over multicast by default, but Azure doesn't support multicast
    # (http://feedback.azure.com/forums/217313-azure-networking/suggestions/547215-multicast-support)
    # keepalived needs to be configured with unicast. Support for unicast was introduced only in version 1.2.8.
    # Default version available in Ubuntu 14.04 is 1.2.7-1ubuntu1.

    # Install a newer version of keepalived from a ppa.
    apt-get -y update && apt-get install -y keepalived

    # Setup keepalived.conf
    KEEPALIVED_CFG=/etc/keepalived/keepalived.conf
    cp -p $KEEPALIVED_CFG $KEEPALIVED_CFG.default


    cat <<EOF | sudo tee /usr/local/sbin/keepalived-action.sh
#!/bin/bash

TYPE=$1
NAME=$2
STATE=$3

modify_probe_status() {
    STATUS=$1

    LB_PROBE_PORT=6443
    LB_PROBE_DEV=eth0

    if [[ $STATUS == "down" ]]; then
        # Add firewall rule to block LB probe port
        /sbin/iptables -A INPUT -p tcp --dport $LB_PROBE_PORT -j REJECT -i $LB_PROBE_DEV
    elif [[ $STATUS == "up" ]]; then
        # Remove all entries to block LB probe port
        RC=0
        while [[ $RC -eq 0 ]]; do
            RC=$(/sbin/iptables -D INPUT -p tcp --dport $LB_PROBE_PORT -j REJECT -i $LB_PROBE_DEV 2>/dev/null; echo $?)
        done
    else
        echo "Unknown probe status"
    fi
}

if [[ "$NAME" == "VI_1" ]]; then
    case $STATE in
        "MASTER") modify_probe_status up
             exit 0
             ;;
        "BACKUP"|"STOP") modify_probe_status down
             exit 0
                          ;;
        "FAULT")  modify_probe_status down
             exit 0
             ;;
        *)        echo "unknown state"
             exit 1
             ;;
    esac
else
        echo "Nothing to do"
        exit 0
fi
EOF

cat <<EOF | sudo tee -a $KEEPALIVED_CFG
vrrp_script chk_appsvc {
    script /usr/local/sbin/keepalived-check-appsvc.sh
    interval 1
    fall 2
    rise 2
}
vrrp_instance VI_1 {
    interface eth0
    authentication {
        auth_type PASS
        auth_pass secr3t
    }
    virtual_router_id 51
    virtual_ipaddress {
        $LB_IP
    }
    track_script {
        chk_appsvc
    }
    notify /usr/local/sbin/keepalived-action.sh
    notify_stop "/usr/local/sbin/keepalived-action.sh INSTANCE VI_1 STOP"
EOF

cat <<EOF | sudo tee /usr/local/sbin/keepalived-check-appsvc.sh
#!/bin/bash

URL="http://localhost"

if [[ $(curl -s -o/dev/null --connect-timeout 0.5 $URL; echo $?) -ne 0 ]]; then
    exit 1
else
    exit 0
fi

EOF

    export MASTERVM_IP="$(host $MASTERVM | awk '/has address/ { print $4 }')"
    export BACKUPVM_IP="$(host $BACKUPVM | awk '/has address/ { print $4 }')"

    if [[ $IS_MASTER == 0 ]]; then
        echo "    state MASTER" >> $KEEPALIVED_CFG
        echo "    priority 101" >> $KEEPALIVED_CFG

        export UNICAST_SRC_IP=$MASTERVM_IP
        export UNICAST_PEER_IP=$BACKUPVM_IP

    else
        echo "    state BACKUP" >> $KEEPALIVED_CFG
        echo "    priority 100" >> $KEEPALIVED_CFG

        export UNICAST_SRC_IP=$BACKUPVM_IP
        export UNICAST_PEER_IP=$MASTERVM_IP

    fi

cat <<EOF | sudo tee -a $KEEPALIVED_CFG
    unicast_src_ip $UNICAST_SRC_IP
    unicast_peer {
        $UNICAST_PEER_IP
    }
}
EOF

    chmod --reference $KEEPALIVED_CFG $KEEPALIVED_CFG

    # Script to perform application level status check
    chmod +x /usr/local/sbin/keepalived-check-appsvc.sh

    # Script to update probe status based on keepalived status
    chmod +x /usr/local/sbin/keepalived-action.sh

    # Enable binding non local VIP
    echo "net.ipv4.ip_nonlocal_bind=1" >> /etc/sysctl.conf
    sysctl -p

    # Restart keepalived
    service keepalived stop && service keepalived start
}


# Setup haproxy
setup_haproxy

# Setup keepalived
# setup_keepalived
