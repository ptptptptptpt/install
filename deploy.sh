#!/bin/bash

programDir=`dirname $0`
programDir=$(readlink -f $programDir)
parentDir="$(dirname $programDir)"
programDirBaseName=$(basename $programDir)


function usage {
    echo "
Usage:
   bash $(basename $0) CONFIG_FILE
"
}


## config
[ "$1" ] || { usage; exit 1; }
[ -f "$1" ] || { echo "Error: $1 not exists or not a file!"; exit 1; }

source $(readlink -f $1) || { echo "'source $(readlink -f $1)' failed!"; exit 1; }

[ "${CONTROL_NODE_PUBLIC_IP}" ] || { echo "Error: CONTROL_NODE_PUBLIC_IP not defined!"; exit 1; }
[ "${CONTROL_NODE_PRIVATE_IP}" ] || { echo "Error: CONTROL_NODE_PRIVATE_IP not defined!"; exit 1; }

[ "${NETWORK_NODES_PRIVATE_IP}" ] || { echo "Error: NETWORK_NODES_PRIVATE_IP not defined!"; exit 1; }
#[ "${NETWORK_NODES_NEUTRON_EXT_IF}" ] || { echo "Error: NETWORK_NODES_NEUTRON_EXT_IF not defined!"; exit 1; }

[ "${COMPUTE_NODES_PRIVATE_IP}" ] || { echo "Error: COMPUTE_NODES_PRIVATE_IP not defined!"; exit 1; }

[ "${STORAGE_NODES_PRIVATE_IP}" ] || { echo "Error: STORAGE_NODES_PRIVATE_IP not defined!"; exit 1; }
[ "${STORAGE_NODES_CEPH_OSD_DATA_DIR}" ] || { echo "Error: STORAGE_NODES_CEPH_OSD_DATA_DIR not defined!"; exit 1; }





###### 所有节点安装 docker
allIpList=`echo "
${CONTROL_NODE_PRIVATE_IP}
${NETWORK_NODES_PRIVATE_IP}
${COMPUTE_NODES_PRIVATE_IP}
${STORAGE_NODES_PRIVATE_IP}" | sed -e 's/,/\n/g' | sort | uniq `

for IP in ${allIpList}; do
    ssh root@${IP} 'mkdir -p /tmp/stackube_install'
    scp ${programDir}/ensure_docker_installed.sh root@${IP}:/tmp/stackube_install/
    ssh root@${IP} "/bin/bash /tmp/stackube_install/ensure_docker_installed.sh"
done



## check distro
source ${programDir}/lib_common.sh || { echo "Error: 'source ${programDir}/lib_common.sh' failed!"; exit 1; }
MSG='Sorry, only CentOS 7.x supported for now.'
if ! is_fedora; then
    echo ${MSG}; exit 1
fi
mainVersion=`echo ${os_RELEASE} | awk -F\. '{print $1}' `
if [ "${os_VENDOR}" == "CentOS" ] && [ "${mainVersion}" == "7" ]; then
    true
else
    echo ${MSG}; exit 1
fi






    yum install centos-release-openstack-ocata.noarch -y  || return 1
    yum install python-openstackclient  || return 1

    source /etc/stackube/openstack/admin-openrc.sh  || return 1
    openstack endpoint list



    source /etc/stackube/openstack/admin-openrc.sh  || return 1
    openstack network create --external --provider-physical-network physnet1 --provider-network-type flat br-ex  || return 1
    openstack network list
    openstack subnet list





function deploy_kubernetes {
    echo "Deploying Kubernetes..."
    /bin/bash ${programDir}/deploy_kubernetes.sh
    if [ "$?" == "0" ]; then
        echo -e "\nKubernetes deployed successfully!\n"
    else
        echo -e "\nKubernetes deployed failed!\n"
        return 1
    fi

}


## for cni 
## 计算节点、网络节点、k8s master节点 都要装
ssh root@${IP} "yum install centos-release-openstack-ocata.noarch -y"
ssh root@${IP} "yum install openvswitch -y"



### 计算节点 host需要安装ceph，供 kubelet 使用
for IP in `echo ${COMPUTE_NODES_PRIVATE_IP} | sed -e 's/,/ /g' ` ; do 
    ssh root@${IP} "yum install centos-release-openstack-ocata.noarch -y"
    ssh root@${IP} "yum install ceph -y"
    ssh root@${IP} "systemctl disable ceph.target ceph-mds.target ceph-mon.target ceph-osd.target"
    scp -r /var/lib/stackube/ceph/ceph_mon_config/*  root@${IP}:/etc/ceph/
    ssh root@${IP} "ceph -s"
    ssh root@${IP} "rbd -p cinder --id cinder --keyring=/etc/ceph/ceph.client.cinder.keyring ls"
done








## kubernetes
export KEYSTONE_URL="https://${API_IP}:5001/v2.0"
export KEYSTONE_ADMIN_URL="https://${API_IP}:35358/v2.0"
export CLUSTER_CIDR="10.244.0.0/16"
export CLUSTER_GATEWAY="10.244.0.1"
export CONTAINER_CIDR="10.244.1.0/24"
export FRAKTI_VERSION="v1.0"


## log
logDir='/var/log/stackube'
logFile="${logDir}/install.log-$(date '+%Y-%m-%d_%H-%M-%S')"
mkdir -p ${logDir} || exit 1


bash ${programDir}/deploy_openstack.sh 2>&1 | tee -a ${logFile}


    echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') All done!"

    echo "
Additional information:
 * File /etc/stackube/openstack/admin-openrc.sh has been created. To use openstack command line tools you need to source the file.
 * File /etc/kubernetes/admin.conf has been created. To use kubectl you need to do 'export KUBECONFIG=/etc/kubernetes/admin.conf'.
 * The installation log file is available at: ${logFile}
"

} 

allStats=(${PIPESTATUS[@]})
[ "${allStats[0]}" == "0" ] || exit 1


exit 0

