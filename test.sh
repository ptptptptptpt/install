#!/bin/bash



programDir=`dirname $0`
programDir=$(readlink -f $programDir)
parentDir="$(dirname $programDir)"
programDirBaseName=$(basename $programDir)

set -o errexit
set -o nounset
set -o pipefail
set -x



function usage {
    echo "
Usage:
   bash $(basename $0) CONFIG_FILE
"
}





######################################
# main
######################################

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




export OPENSTACK_ENDPOINT_IP="${CONTROL_NODE_PRIVATE_IP}"
export KEYSTONE_API_IP="${CONTROL_NODE_PRIVATE_IP}"
export NEUTRON_API_IP="${CONTROL_NODE_PRIVATE_IP}"
export CINDER_API_IP="${CONTROL_NODE_PRIVATE_IP}"

export MYSQL_HOST="${CONTROL_NODE_PRIVATE_IP}"
export MYSQL_ROOT_PWD=${MYSQL_ROOT_PWD:-MysqlRoot123}
export MYSQL_KEYSTONE_PWD=${MYSQL_KEYSTONE_PWD:-MysqlKeystone123}
export MYSQL_NEUTRON_PWD=${MYSQL_NEUTRON_PWD:-MysqlNeutron123}

export RABBITMQ_HOST="${CONTROL_NODE_PRIVATE_IP}"
export RABBITMQ_PWD=${RABBITMQ_PWD:-rabbitmq123}

export KEYSTONE_ADMIN_PWD=${KEYSTONE_ADMIN_PWD:-KeystoneAdmin123}
export KEYSTONE_NEUTRON_PWD=${KEYSTONE_NEUTRON_PWD:-KeystoneNeutron123}

## ceph
export CEPH_MON_PUBLIC_IP="${CONTROL_NODE_PRIVATE_IP}"
export CEPH_FSID=${CEPH_FSID:-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}

## cinder
export CINDER_API_IP="${CONTROL_NODE_PRIVATE_IP}"
export KEYSTONE_CINDER_PWD=${KEYSTONE_CINDER_PWD:-KeystoneCinder123}
export MYSQL_CINDER_PWD=${MYSQL_CINDER_PWD:-MysqlCinder123}





###### 所有节点安装 docker
allIpList=`echo "
${CONTROL_NODE_PRIVATE_IP}
${NETWORK_NODES_PRIVATE_IP}
${COMPUTE_NODES_PRIVATE_IP}
${STORAGE_NODES_PRIVATE_IP}" | sed -e 's/,/\n/g' | sort | uniq `

for IP in ${allIpList}; do
    ssh root@${IP} 'mkdir /tmp/stackube_install'
    scp ${programDir}/openstack/ensure_docker_installed.sh root@${IP}:/tmp/stackube_install/
    ssh root@${IP} "/bin/bash /tmp/stackube_install/ensure_docker_installed.sh"
done


###### 所有节点 部署 toolbox
for IP in ${allIpList}; do
    ssh root@${IP} 'mkdir -p /etc/stackube/openstack /tmp/stackube_install'
    scp -r ${programDir}/openstack/config_openstack/kolla-toolbox root@${IP}:/etc/stackube/openstack/

    scp ${programDir}/openstack/deploy_openstack_kolla_toolbox.sh root@${IP}:/tmp/stackube_install/
    ssh root@${IP} "/bin/bash /tmp/stackube_install/deploy_openstack_kolla_toolbox.sh"
done



########## 控制节点 部署

# db, mq, haproxy
/bin/bash ${programDir}/openstack/deploy_openstack_mariadb.sh
/bin/bash ${programDir}/openstack/deploy_openstack_rabbitmq.sh
/bin/bash ${programDir}/openstack/deploy_openstack_haproxy.sh

# keystone
/bin/bash ${programDir}/openstack/deploy_openstack_keystone.sh


# neutron server
function process_neutron_conf {
    local configFile="$1"
    sed -i "s/__RABBITMQ_HOST__/${RABBITMQ_HOST}/g" ${configFile}
    sed -i "s/__RABBITMQ_PWD__/${RABBITMQ_PWD}/g" ${configFile}
    sed -i "s/__NEUTRON_API_IP__/${NEUTRON_API_IP}/g" ${configFile}
    sed -i "s/__MYSQL_HOST__/${MYSQL_HOST}/g" ${configFile}
    sed -i "s/__OPENSTACK_ENDPOINT_IP__/${OPENSTACK_ENDPOINT_IP}/g" ${configFile}
    sed -i "s/__KEYSTONE_NEUTRON_PWD__/${KEYSTONE_NEUTRON_PWD}/g" ${configFile}
    sed -i "s/__MYSQL_NEUTRON_PWD__/${MYSQL_NEUTRON_PWD}/g" ${configFile}
}

mkdir -p /etc/stackube/openstack
cp -a ${programDir}/openstack/config_openstack/neutron-server /etc/stackube/openstack/
process_neutron_conf /etc/stackube/openstack/neutron-server/neutron.conf

source /etc/stackube/openstack/admin-openrc.sh 
cp -f ${OS_CACERT} /etc/stackube/openstack/neutron-server/haproxy-ca.crt

/bin/bash ${programDir}/openstack/deploy_openstack_neutron_server.sh


# ceph-mon
/bin/bash ${programDir}/ceph/deploy_ceph_mon.sh


## cinder api
function process_cinder_conf {
    local cinderConfigFile="$1"
    sed -i "s/__CINDER_API_IP__/${CINDER_API_IP}/g" ${cinderConfigFile}
    sed -i "s/__RABBITMQ_HOST__/${RABBITMQ_HOST}/g" ${cinderConfigFile}
    sed -i "s/__RABBITMQ_PWD__/${RABBITMQ_PWD}/g" ${cinderConfigFile}
    sed -i "s/__MYSQL_CINDER_PWD__/${MYSQL_CINDER_PWD}/g" ${cinderConfigFile}
    sed -i "s/__MYSQL_HOST__/${MYSQL_HOST}/g" ${cinderConfigFile}
    sed -i "s/__OPENSTACK_ENDPOINT_IP__/${OPENSTACK_ENDPOINT_IP}/g" ${cinderConfigFile}
    sed -i "s/__KEYSTONE_CINDER_PWD__/${KEYSTONE_CINDER_PWD}/g" ${cinderConfigFile}
}
mkdir -p /etc/stackube/openstack
cp -a ${programDir}/openstack/config_openstack/cinder-api /etc/stackube/openstack/
process_cinder_conf /etc/stackube/openstack/cinder-api/cinder.conf

source /etc/stackube/openstack/admin-openrc.sh 
cp -f ${OS_CACERT} /etc/stackube/openstack/cinder-api/haproxy-ca.crt

/bin/bash ${programDir}/openstack/deploy_openstack_cinder_api.sh


## cinder scheduler
mkdir -p /etc/stackube/openstack
cp -a ${programDir}/openstack/config_openstack/cinder-scheduler /etc/stackube/openstack/
cp -f /etc/stackube/openstack/cinder-api/cinder.conf  /etc/stackube/openstack/cinder-scheduler/
/bin/bash ${programDir}/openstack/deploy_openstack_cinder_scheduler.sh




####### 网络节点 部署

## neutron l3_agent
for IP in `echo ${NETWORK_NODES_PRIVATE_IP} | sed -e 's/,/ /g' ` ; do 
    ssh root@${IP} 'mkdir -p /etc/stackube/openstack /tmp/stackube_install'
    scp -r ${programDir}/openstack/config_openstack/neutron-l3-agent root@${IP}:/etc/stackube/openstack/
    scp -r /etc/stackube/openstack/neutron-server/neutron.conf \
           ${programDir}/openstack/config_openstack/neutron-server/ml2_conf.ini  root@${IP}:/etc/stackube/openstack/neutron-l3-agent/

    scp ${programDir}/openstack/deploy_openstack_neutron_l3_agent.sh root@${IP}:/tmp/stackube_install/
    ssh root@${IP} "export OVSDB_IP='${IP}'
                    export ML2_LOCAL_IP='${IP}'
                    /bin/bash /tmp/stackube_install/deploy_openstack_neutron_l3_agent.sh"
done

## neutron dhcp_agent
for IP in `echo ${NETWORK_NODES_PRIVATE_IP} | sed -e 's/,/ /g' ` ; do 
    ssh root@${IP} 'mkdir -p /etc/stackube/openstack /tmp/stackube_install'
    scp -r ${programDir}/openstack/config_openstack/neutron-dhcp-agent root@${IP}:/etc/stackube/openstack/
    scp -r /etc/stackube/openstack/neutron-server/neutron.conf \
           ${programDir}/openstack/config_openstack/neutron-server/ml2_conf.ini  root@${IP}:/etc/stackube/openstack/neutron-dhcp-agent/

    scp ${programDir}/openstack/deploy_openstack_neutron_dhcp_agent.sh root@${IP}:/tmp/stackube_install/
    ssh root@${IP} "export OVSDB_IP='${IP}'
                    export ML2_LOCAL_IP='${IP}'
                    /bin/bash /tmp/stackube_install/deploy_openstack_neutron_dhcp_agent.sh"
done


## neutron lbaas_agent
for IP in `echo ${NETWORK_NODES_PRIVATE_IP} | sed -e 's/,/ /g' ` ; do 
    ssh root@${IP} 'mkdir -p /etc/stackube/openstack /tmp/stackube_install'
    scp -r ${programDir}/openstack/config_openstack/neutron-lbaas-agent root@${IP}:/etc/stackube/openstack/
    scp -r /etc/stackube/openstack/neutron-server/neutron.conf \
           ${programDir}/openstack/config_openstack/neutron-server/{ml2_conf.ini,neutron_lbaas.conf}  root@${IP}:/etc/stackube/openstack/neutron-lbaas-agent/

    scp ${programDir}/openstack/deploy_openstack_neutron_lbaas_agent.sh root@${IP}:/tmp/stackube_install/
    ssh root@${IP} "export OVSDB_IP='${IP}'
                    export ML2_LOCAL_IP='${IP}'
                    export KEYSTONE_API_IP='${KEYSTONE_API_IP}'
                    export KEYSTONE_NEUTRON_PWD='${KEYSTONE_NEUTRON_PWD}'
                    /bin/bash /tmp/stackube_install/deploy_openstack_neutron_lbaas_agent.sh"
done


###### 存储节点 部署 ceph-osd
storageIpList=(`echo "${STORAGE_NODES_PRIVATE_IP}" | sed -e 's/,/\n/g'`)
osdDataDirList=(`echo "${STORAGE_NODES_CEPH_OSD_DATA_DIR}" | sed -e 's/,/\n/g'`)
[ ${#storageIpList[@]} -eq ${#osdDataDirList[@]} ] || exit 1

MAX=$((${#storageIpList[@]} - 1))
for i in `seq 0 ${MAX}`; do
    IP="${storageIpList[$i]}"
    dataDir="${osdDataDirList[$i]}"
    echo -e "\n------ ${IP} ${dataDir} ------"
    ssh root@${IP} 'mkdir -p /etc/stackube/ceph /tmp/stackube_install'
    scp -r ${programDir}/ceph/config_ceph/ceph-osd root@${IP}:/etc/stackube/ceph/
    scp -r /var/lib/stackube/ceph/ceph_mon_config/{ceph.client.admin.keyring,ceph.conf} root@${IP}:/etc/stackube/ceph/ceph-osd/

    scp ${programDir}/ceph/deploy_ceph_osd.sh root@${IP}:/tmp/stackube_install/
    ssh root@${IP} "export CEPH_OSD_PUBLIC_IP='${IP}'
                    export CEPH_OSD_CLUSTER_IP='${IP}'
                    export CEPH_OSD_DATA_DIR='${dataDir}'
                    /bin/bash /tmp/stackube_install/deploy_ceph_osd.sh"
done

docker exec stackube_ceph_mon ceph -s



###### 选择一个或多个节点部署 cinder volume
docker exec stackube_ceph_mon ceph osd pool create cinder 128 128
docker exec stackube_ceph_mon ceph auth get-or-create client.cinder mon 'allow r' \
                 osd 'allow class-read object_prefix rbd_children, allow rwx pool=cinder'
docker exec stackube_ceph_mon /bin/bash -c 'ceph auth get-or-create client.cinder | tee /etc/ceph/ceph.client.cinder.keyring'

for IP in ${CONTROL_NODE_PRIVATE_IP} ; do 
    ssh root@${IP} 'mkdir -p /etc/stackube/openstack /tmp/stackube_install'
    scp -r ${programDir}/openstack/config_openstack/cinder-volume root@${IP}:/etc/stackube/openstack/
    scp -r /etc/stackube/openstack/cinder-api/cinder.conf \
           /var/lib/stackube/ceph/ceph_mon_config/{ceph.conf,ceph.client.cinder.keyring}  root@${IP}:/etc/stackube/openstack/cinder-volume/

    scp ${programDir}/openstack/deploy_openstack_cinder_volume.sh root@${IP}:/tmp/stackube_install/
    ssh root@${IP} "/bin/bash /tmp/stackube_install/deploy_openstack_cinder_volume.sh"
done






######## 网络节点 和 计算节点 部署 openvswitch_agent
allIpList=`echo "
${NETWORK_NODES_PRIVATE_IP}
${COMPUTE_NODES_PRIVATE_IP}" | sed -e 's/,/\n/g' | sort | uniq `
for IP in ${allIpList}; do
    ssh root@${IP} 'mkdir -p /etc/stackube/openstack /tmp/stackube_install'
    scp -r ${programDir}/openstack/config_openstack/{openvswitch-db-server,openvswitch-vswitchd,neutron-openvswitch-agent} root@${IP}:/etc/stackube/openstack/
    scp -r /etc/stackube/openstack/neutron-server/neutron.conf ${programDir}/openstack/config_openstack/neutron-server/ml2_conf.ini  root@${IP}:/etc/stackube/openstack/neutron-openvswitch-agent/

    scp ${programDir}/openstack/deploy_openstack_neutron_openvswitch_agent.sh root@${IP}:/tmp/stackube_install/
    ssh root@${IP} "export OVSDB_IP='${IP}'
                    export ML2_LOCAL_IP='${IP}'
                    /bin/bash /tmp/stackube_install/deploy_openstack_neutron_openvswitch_agent.sh"
done

# 网络节点 配置 NEUTRON_EXT_IF 
networkIpList=(`echo "${NETWORK_NODES_PRIVATE_IP}" | sed -e 's/,/\n/g'`)
neutronExtIfList=(`echo "${NETWORK_NODES_NEUTRON_EXT_IF}" | sed -e 's/,/\n/g'`)
[ ${#networkIpList[@]} -eq ${#neutronExtIfList[@]} ] || exit 1
MAX=$((${#networkIpList[@]} - 1))
for i in `seq 0 ${MAX}`; do
    IP="${networkIpList[$i]}"
    extIf="${neutronExtIfList[$i]}"
    echo -e "\n------ ${IP} ${extIf} ------"
    ssh root@${IP} "docker exec stackube_openstack_openvswitch_db /usr/local/bin/kolla_ensure_openvswitch_configured br-ex ${extIf}"
done







### 计算节点 host需要安装ceph，供 kubelet 使用
for IP in `echo ${COMPUTE_NODES_PRIVATE_IP} | sed -e 's/,/ /g' ` ; do 
    ssh root@${IP} "yum install centos-release-openstack-ocata.noarch -y"
    ssh root@${IP} "yum install ceph -y"
    ssh root@${IP} "systemctl disable ceph.target ceph-mds.target ceph-mon.target ceph-osd.target"
    scp -r /var/lib/stackube/ceph/ceph_mon_config/*  root@${IP}:/etc/ceph/
    ssh root@${IP} "ceph -s"
    ssh root@${IP} "rbd -p cinder --id cinder --keyring=/etc/ceph/ceph.client.cinder.keyring ls"
done



