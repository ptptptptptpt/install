#!/bin/bash



programDir=`dirname $0`
programDir=$(readlink -f $programDir)
parentDir="$(dirname $programDir)"
programDirBaseName=$(basename $programDir)

set -o errexit
set -o nounset
set -o pipefail
set -x





## 控制节点

/bin/bash ${programDir}/openstack/deploy_kolla_toolbox.sh


export MYSQL_ROOT_PWD='mysql123'
/bin/bash ${programDir}/openstack/deploy_mariadb.sh



export RABBITMQ_PWD='rabbitl123'
/bin/bash ${programDir}/openstack/deploy_rabbitmq.sh


export OPENSTACK_ENDPOINT_IP='10.100.143.135'
export KEYSTONE_API_IP='10.100.143.135'
export NEUTRON_API_IP='10.100.143.135'
export CINDER_API_IP='10.100.143.135'
/bin/bash ${programDir}/openstack/deploy_haproxy.sh



export OPENSTACK_ENDPOINT_IP='10.100.143.135'
export KEYSTONE_API_IP='10.100.143.135'
export MYSQL_HOST='10.100.143.135'
export MYSQL_ROOT_PWD='mysql123'
export MYSQL_KEYSTONE_PWD='mysqkeystonel123'
export KEYSTONE_ADMIN_PWD='keystoneadminl123'
/bin/bash ${programDir}/openstack/deploy_openstack_keystone.sh






#### neutron
export MYSQL_ROOT_PWD='mysql123'
export KEYSTONE_ADMIN_PWD='keystoneadminl123'

export OPENSTACK_ENDPOINT_IP='10.100.143.135'
export RABBITMQ_HOST='10.100.143.135'
export RABBITMQ_PWD='rabbitl123'
export MYSQL_HOST='10.100.143.135'

export NEUTRON_API_IP='10.100.143.135'
export KEYSTONE_NEUTRON_PWD='keystoneneutron123'
export MYSQL_NEUTRON_PWD='mysqlneutron123'


function process_neutron_conf {
    local configFile="$1"
    sed -i "s/__RABBITMQ_HOST__/${RABBITMQ_HOST}/g" ${configFile}
    sed -i "s/__RABBITMQ_PWD__/${RABBITMQ_PWD}/g" ${configFile}
    sed -i "s/__NEUTRON_API_IP__/${NEUTRON_API_IP}/g" ${configFile}
    sed -i "s/__MYSQL_HOST__/${MYSQL_HOST}/g" ${configFile}
    sed -i "s/__OPENSTACK_ENDPOINT_IP__/${OPENSTACK_ENDPOINT_IP}/g" ${configFile}
    sed -i "s/__NEUTRON_KEYSTONE_PWD__/${KEYSTONE_NEUTRON_PWD}/g" ${configFile}
    sed -i "s/__MYSQL_NEUTRON_PWD__/${MYSQL_NEUTRON_PWD}/g" ${configFile}
}


## config files
mkdir -p /etc/stackube/openstack
cp -a ${programDir}/openstack/config_openstack/neutron-server /etc/stackube/openstack/
process_neutron_conf /etc/stackube/openstack/neutron-server/neutron.conf
## for OS_CACERT
source /etc/stackube/openstack/admin-openrc.sh 
cp -f ${OS_CACERT} /etc/stackube/openstack/neutron-server/haproxy-ca.crt


/bin/bash ${programDir}/openstack/deploy_openstack_neutron_server.sh




## 网络节点 和 计算节点 部署 openvswitch_agent

## 网络节点 NEUTRON_EXT_IF 不为空，计算节点为空

(
set -x

for IP in '10.100.143.135'  ; do 
    ssh root@${IP} 'mkdir -p /etc/stackube/openstack /tmp/stackube_install'
    scp -r ${programDir}/openstack/config_openstack/{openvswitch-db-server,openvswitch-vswitchd,neutron-openvswitch-agent} root@${IP}:/etc/stackube/openstack/
    scp -r /etc/stackube/openstack/neutron-server/neutron.conf ${programDir}/openstack/config_openstack/neutron-server/ml2_conf.ini  root@${IP}:/etc/stackube/openstack/neutron-openvswitch-agent/

    scp ${programDir}/openstack/deploy_openstack_neutron_openvswitch_agent.sh root@${IP}:/tmp/stackube_install/
    ssh root@${IP} "export OVSDB_IP='${IP}'
                    export ML2_LOCAL_IP='${IP}'
                    export NEUTRON_EXT_IF='veth_2_b'
                    /bin/bash /tmp/stackube_install/deploy_openstack_neutron_openvswitch_agent.sh"

done
)




## 网络节点 部署 l3_agent
(
set -x

for IP in '10.100.143.135'  ; do 
    ssh root@${IP} 'mkdir -p /etc/stackube/openstack /tmp/stackube_install'
    scp -r ${programDir}/openstack/config_openstack/neutron-l3-agent root@${IP}:/etc/stackube/openstack/
    scp -r /etc/stackube/openstack/neutron-server/neutron.conf \
           ${programDir}/openstack/config_openstack/neutron-server/ml2_conf.ini  root@${IP}:/etc/stackube/openstack/neutron-l3-agent/

    scp ${programDir}/openstack/deploy_openstack_neutron_l3_agent.sh root@${IP}:/tmp/stackube_install/
    ssh root@${IP} "export OVSDB_IP='${IP}'
                    export ML2_LOCAL_IP='${IP}'
                    /bin/bash /tmp/stackube_install/deploy_openstack_neutron_l3_agent.sh"
done
)




## 网络节点 部署 dhcp_agent
(
set -x

for IP in '10.100.143.135'  ; do 
    ssh root@${IP} 'mkdir -p /etc/stackube/openstack /tmp/stackube_install'
    scp -r ${programDir}/openstack/config_openstack/neutron-dhcp-agent root@${IP}:/etc/stackube/openstack/
    scp -r /etc/stackube/openstack/neutron-server/neutron.conf \
           ${programDir}/openstack/config_openstack/neutron-server/ml2_conf.ini  root@${IP}:/etc/stackube/openstack/neutron-dhcp-agent/

    scp ${programDir}/openstack/deploy_openstack_neutron_dhcp_agent.sh root@${IP}:/tmp/stackube_install/
    ssh root@${IP} "export OVSDB_IP='${IP}'
                    export ML2_LOCAL_IP='${IP}'
                    /bin/bash /tmp/stackube_install/deploy_openstack_neutron_dhcp_agent.sh"
done
)






## 网络节点 部署 lbaas_agent
(
set -x

for IP in '10.100.143.135'  ; do 
    ssh root@${IP} 'mkdir -p /etc/stackube/openstack /tmp/stackube_install'
    scp -r ${programDir}/openstack/config_openstack/neutron-lbaas-agent root@${IP}:/etc/stackube/openstack/
    scp -r /etc/stackube/openstack/neutron-server/neutron.conf \
           ${programDir}/openstack/config_openstack/neutron-server/{ml2_conf.ini,neutron_lbaas.conf}  root@${IP}:/etc/stackube/openstack/neutron-lbaas-agent/

    scp ${programDir}/openstack/deploy_openstack_neutron_lbaas_agent.sh root@${IP}:/tmp/stackube_install/
    ssh root@${IP} "export OVSDB_IP='${IP}'
                    export ML2_LOCAL_IP='${IP}'
                    export KEYSTONE_API_IP='10.100.143.135'
                    export KEYSTONE_NEUTRON_PWD='keystoneneutron123'
                    /bin/bash /tmp/stackube_install/deploy_openstack_neutron_lbaas_agent.sh"
done
)






## 控制节点部署 ceph-mon
export CEPH_MON_PUBLIC_IP='10.100.143.135'
export CEPH_FSID='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
/bin/bash ${programDir}/ceph/deploy_ceph_mon.sh





## 存储节点 部署 ceph-osd
(
set -x

for IP in '10.100.143.135'  ; do
    ssh root@${IP} 'mkdir -p /etc/stackube/ceph /tmp/stackube_install'
    scp -r ${programDir}/ceph/config_ceph/ceph-osd root@${IP}:/etc/stackube/ceph/
    scp -r /var/lib/stackube/ceph/ceph_mon_config/{ceph.client.admin.keyring,ceph.conf} root@${IP}:/etc/stackube/ceph/ceph-osd/

    scp ${programDir}/ceph/deploy_ceph_osd.sh root@${IP}:/tmp/stackube_install/
    ssh root@${IP} "export CEPH_OSD_PUBLIC_IP='${IP}'
                    export CEPH_OSD_CLUSTER_IP='${IP}'
                    export CEPH_OSD_DATA_DIR='/var/lib/stackube/openstack/ceph_osd'
                    /bin/bash /tmp/stackube_install/deploy_ceph_osd.sh"

    docker exec stackube_ceph_mon ceph -s

done
)



exit 0

### 计算节点 host需要安装ceph，供 kubelet 使用
yum install centos-release-openstack-ocata.noarch -y
yum install ceph -y 
systemctl disable ceph.target ceph-mds.target ceph-mon.target ceph-osd.target
cp -f /var/lib/stackube/ceph/ceph_mon_config/* /etc/ceph/
ceph -s




















