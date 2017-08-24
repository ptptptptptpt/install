#!/bin/bash

programDir=`dirname $0`
programDir=$(readlink -f $programDir)
parentDir="$(dirname $programDir)"
programDirBaseName=$(basename $programDir)

set -o errexit
set -o nounset
set -o pipefail
set -x


source $(readlink -f $1)

[ "${CONTROL_NODE_PUBLIC_IP}" ]
[ "${CONTROL_NODE_PRIVATE_IP}" ]
[ "${NETWORK_NODES_PRIVATE_IP}" ]
[ "${COMPUTE_NODES_PRIVATE_IP}" ]


export KUBERNETES_API_PUBLIC_IP="${CONTROL_NODE_PUBLIC_IP}"
export KUBERNETES_API_PRIVATE_IP="${CONTROL_NODE_PRIVATE_IP}"
export KEYSTONE_URL="https://${CONTROL_NODE_PRIVATE_IP}:5001/v2.0"
export KEYSTONE_ADMIN_URL="https://${CONTROL_NODE_PRIVATE_IP}:35358/v2.0"
export CLUSTER_CIDR="10.244.0.0/16"
export CLUSTER_GATEWAY="10.244.0.1"
export CONTAINER_CIDR="10.244.1.0/24"
export FRAKTI_VERSION="v1.0"



########## control & compute nodes ##########

allIpList=`echo "
${CONTROL_NODE_PRIVATE_IP}
${COMPUTE_NODES_PRIVATE_IP}" | sed -e 's/,/\n/g' | sort | uniq `

# kubeadm kubectl kubelet
for IP in ${allIpList}; do
    ssh root@${IP} 'mkdir -p /tmp/stackube_install'
    scp ${programDir}/kubernetes/deploy_kubeadm_kubectl_kubelet.sh root@${IP}:/tmp/stackube_install/
    ssh root@${IP} "/bin/bash /tmp/stackube_install/deploy_kubeadm_kubectl_kubelet.sh"
done

# hyperd frakti
for IP in ${allIpList}; do
    ssh root@${IP} 'mkdir -p /tmp/stackube_install'
    scp ${programDir}/kubernetes/deploy_hyperd_frakti.sh root@${IP}:/tmp/stackube_install/
    ssh root@${IP} "/bin/bash /tmp/stackube_install/deploy_hyperd_frakti.sh"
done


# kubernetes master
sed -i "s|__KEYSTONE_URL__|${KEYSTONE_URL}|g" ${programDir}/kubernetes/kubeadm.yaml
sed -i "s|__POD_NET_CIDR__|${CLUSTER_CIDR}|g" ${programDir}/kubernetes/kubeadm.yaml
sed -i "s/__KUBERNETES_API_PUBLIC_IP__/${KUBERNETES_API_PUBLIC_IP}/g" ${programDir}/kubernetes/kubeadm.yaml
sed -i "s/__KUBERNETES_API_PRIVATE_IP__/${KUBERNETES_API_PRIVATE_IP}/g" ${programDir}/kubernetes/kubeadm.yaml
/bin/bash ${programDir}/kubernetes/deploy_kubernetes_init_master.sh




## 按需配置
# Enable schedule pods on the master for testing.
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl taint nodes --all node-role.kubernetes.io/master- 




sleep 15

/bin/bash ${programDir}/kubernetes/deploy_kubernetes_certificate_approve.sh

sleep 5

kubectl get nodes
kubectl get csr --all-namespaces




exit 0



## for cni 
## 计算节点、网络节点、k8s master节点 都要装

可是控制节点没有 ovs agent， 会不会影响 cni 调 ovs ？



allIpList=`echo "
${CONTROL_NODE_PRIVATE_IP}
${COMPUTE_NODES_PRIVATE_IP}" | sed -e 's/,/\n/g' | sort | uniq `
for IP in ${allIpList}; do
    ssh root@${IP} "yum install centos-release-openstack-ocata.noarch -y"
    ssh root@${IP} "yum install openvswitch -y"
done



### compute nodes: install ceph for kubelet
for IP in `echo ${COMPUTE_NODES_PRIVATE_IP} | sed -e 's/,/ /g' ` ; do 
    ssh root@${IP} "yum install centos-release-openstack-ocata.noarch -y"
    ssh root@${IP} "yum install ceph -y"
    ssh root@${IP} "systemctl disable ceph.target ceph-mds.target ceph-mon.target ceph-osd.target"
    scp -r /var/lib/stackube/ceph/ceph_mon_config/*  root@${IP}:/etc/ceph/
    ssh root@${IP} "ceph -s"
    ssh root@${IP} "rbd -p cinder --id cinder --keyring=/etc/ceph/ceph.client.cinder.keyring ls"
done




exit 0
