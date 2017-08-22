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

/bin/bash ${programDir}/deploy_kolla_toolbox.sh


export MYSQL_ROOT_PWD='mysql123'
/bin/bash ${programDir}/deploy_mariadb.sh



export RABBITMQ_PWD='rabbitl123'
/bin/bash ${programDir}/deploy_rabbitmq.sh


export OPENSTACK_ENDPOINT_IP='10.100.143.135'
export KEYSTONE_API_IP='10.100.143.135'
export NEUTRON_API_IP='10.100.143.135'
export CINDER_API_IP='10.100.143.135'
/bin/bash ${programDir}/deploy_haproxy.sh



export OPENSTACK_ENDPOINT_IP='10.100.143.135'
export KEYSTONE_API_IP='10.100.143.135'
export MYSQL_HOST='10.100.143.135'
export MYSQL_ROOT_PWD='mysql123'
export MYSQL_KEYSTONE_PWD='mysqkeystonel123'
export KEYSTONE_ADMIN_PWD='keystoneadminl123'
/bin/bash ${programDir}/deploy_openstack_keystone.sh





export OPENSTACK_ENDPOINT_IP='10.100.143.135'
export RABBITMQ_HOST='10.100.143.135'
export RABBITMQ_PWD='rabbitl123'
export MYSQL_HOST='10.100.143.135'
export MYSQL_ROOT_PWD='mysql123'
export KEYSTONE_ADMIN_PWD='keystoneadminl123'

export NEUTRON_API_IP='10.100.143.135'
export KEYSTONE_NEUTRON_PWD='keystoneneutron123'
export MYSQL_NEUTRON_PWD='mysqlneutron123'
/bin/bash ${programDir}/deploy_openstack_neutron_server.sh








for IP in '10.100.143.135'  ; do 
    ssh root@${IP} 'mkdir -p /etc/stackube/openstack /tmp/stackube_install'
    scp -r ${programDir}/config_openstack/{openvswitch-db-server,openvswitch-vswitchd,neutron-openvswitch-agent} root@${IP}:/etc/stackube/openstack/
    #source /etc/stackube/openstack/admin-openrc.sh 
    #scp ${OS_CACERT} root@${IP}:/etc/stackube/openstack/neutron-server/haproxy-ca.crt
    scp ${programDir}/deploy_openstack_neutron_openvswitch_agent.sh root@${IP}:/tmp/stackube_install/
    ssh root@${IP} "export OPENSTACK_ENDPOINT_IP='10.100.143.135'
                    export RABBITMQ_HOST='10.100.143.135'
                    export RABBITMQ_PWD='rabbitl123'
                    export MYSQL_HOST='10.100.143.135'
                    export MYSQL_ROOT_PWD='mysql123'
                    export KEYSTONE_ADMIN_PWD='keystoneadminl123'
                    export NEUTRON_API_IP='10.100.143.135'
                    export KEYSTONE_NEUTRON_PWD='keystoneneutron123'
                    export MYSQL_NEUTRON_PWD='mysqlneutron123'
                    export OVSDB_IP='${IP}'
                    export ML2_LOCAL_IP='${IP}'
                    /bin/bash /tmp/stackube_install/deploy_openstack_neutron_openvswitch_agent.sh"

done
