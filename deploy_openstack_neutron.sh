#!/bin/bash
#
# Dependencies:
#
# - ``OVSDB_IP``
# - ``OPENSTACK_ENDPOINT_IP``
# - ``RABBITMQ_HOST``, ``RABBITMQ_PWD``
# - ``MYSQL_HOST``, ``MYSQL_ROOT_PWD``
# - ``KEYSTONE_ADMIN_PWD``, ``NEUTRON_API_IP``
# - ``KEYSTONE_NEUTRON_PWD``, ``MYSQL_NEUTRON_PWD``
# - ``NEUTRON_EXT_IF`` must be defined
#


programDir=`dirname $0`
programDir=$(readlink -f $programDir)
parentDir="$(dirname $programDir)"
programDirBaseName=$(basename $programDir)

set -o errexit
set -o nounset
set -o pipefail
set -x

## log dir
mkdir -p /var/log/stackube/openstack
chmod 777 /var/log/stackube/openstack


## for OS_CACERT
source /etc/stackube/openstack/admin-openrc.sh


## sysctl
cat >> /etc/sysctl.conf << EOF

net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0

EOF

sysctl -p



## openvswitch-db-server
sed -i "s/__THE_WORK_IP__/${API_IP}/g" /etc/stackube/openstack/openvswitch-db-server/config.json
mkdir -p /var/lib/stackube/openstack/openvswitch
docker run -d  --net host  \
    --name stackube_openvswitch_db  \
    -v /etc/stackube/openstack/openvswitch-db-server/:/var/lib/kolla/config_files/:ro  \
    -v /var/log/stackube/openstack:/var/log/kolla/:rw  \
    -v /var/lib/stackube/openstack/openvswitch/:/var/lib/openvswitch/:rw  \
    -v /run:/run:shared  \
    \
    -e "KOLLA_SERVICE_NAME=openvswitch-db"  \
    -e "KOLLA_CONFIG_STRATEGY=COPY_ALWAYS" \
    \
    --restart unless-stopped \
    kolla/centos-binary-openvswitch-db-server:4.0.0

sleep 10

# config br-ex
docker exec -it stackube_openvswitch_db /usr/local/bin/kolla_ensure_openvswitch_configured br-ex ${NEUTRON_EXT_IF}


## openvswitch-vswitchd
docker run -d  --net host  \
    --name stackube_openvswitch_vswitchd  \
    -v /etc/stackube/openstack/openvswitch-vswitchd/:/var/lib/kolla/config_files/:ro  \
    -v /var/log/stackube/openstack:/var/log/kolla/:rw  \
    -v /run:/run:shared  \
    -v /lib/modules:/lib/modules:ro  \
    \
    -e "KOLLA_SERVICE_NAME=openvswitch-vswitchd"  \
    -e "KOLLA_CONFIG_STRATEGY=COPY_ALWAYS" \
    \
    --restart unless-stopped \
    --privileged  \
    kolla/centos-binary-openvswitch-vswitchd:4.0.0

sleep 5




### neutron

## register - Creating the Neutron service and endpoint
for IF in 'admin' 'internal' 'public'; do 
    docker exec -t stackube_kolla_toolbox /usr/bin/ansible localhost  -m kolla_keystone_service \
        -a "service_name=neutron
            service_type=network
            description='Openstack Networking'
            endpoint_region=RegionOne
            url='https://${API_IP}:9697/'
            interface='${IF}'
            region_name=RegionOne
            auth='{{ openstack_keystone_auth }}'
            verify=False  " \
        -e "{'openstack_keystone_auth': {
               'auth_url': 'https://${API_IP}:35358/v3',
               'username': 'admin',
               'password': '${KEYSTONE_ADMIN_PWD}',
               'project_name': 'admin',
               'domain_name': 'default' } 
            }"
done


## register - Creating the Neutron project, user, and role
docker exec -t stackube_kolla_toolbox /usr/bin/ansible localhost  -m kolla_keystone_user \
    -a "project=service
        user=neutron
        password=${KEYSTONE_NEUTRON_PWD}
        role=admin
        region_name=RegionOne
        auth='{{ openstack_keystone_auth }}'
        verify=False  " \
    -e "{'openstack_keystone_auth': {
           'auth_url': 'https://${API_IP}:35358/v3',
           'username': 'admin',
           'password': '${KEYSTONE_ADMIN_PWD}',
           'project_name': 'admin',
           'domain_name': 'default' } 
        }"


# bootstrap - Creating Neutron database
docker exec -t stackube_kolla_toolbox /usr/bin/ansible localhost   -m mysql_db \
    -a "login_host=${API_IP}
        login_port=3306
        login_user=root
        login_password=${MYSQL_ROOT_PWD}
        name=neutron"

# bootstrap - Creating Neutron database user and setting permissions
docker exec -t stackube_kolla_toolbox /usr/bin/ansible localhost   -m mysql_user \
    -a "login_host=${API_IP}
        login_port=3306
        login_user=root
        login_password=${MYSQL_ROOT_PWD}
        name=neutron
        password=${MYSQL_NEUTRON_PWD}
        host=%
        priv='neutron.*:ALL'
        append_privs=yes"


# bootstrap_service - Running Neutron bootstrap container
sed -i "s/__THE_WORK_IP__/${API_IP}/g" /etc/stackube/openstack/neutron-server/ml2_conf.ini

sed -i "s/__THE_WORK_IP__/${API_IP}/g" /etc/stackube/openstack/neutron-server/neutron.conf
sed -i "s/__NEUTRON_KEYSTONE_PWD__/${KEYSTONE_NEUTRON_PWD}/g" /etc/stackube/openstack/neutron-server/neutron.conf
sed -i "s/__MYSQL_NEUTRON_PWD__/${MYSQL_NEUTRON_PWD}/g" /etc/stackube/openstack/neutron-server/neutron.conf
sed -i "s/__RABBITMQ_PWD__/${RABBITMQ_PWD}/g" /etc/stackube/openstack/neutron-server/neutron.conf

sed -i "s/__THE_WORK_IP__/${API_IP}/g" /etc/stackube/openstack/neutron-server/neutron_lbaas.conf
sed -i "s/__NEUTRON_KEYSTONE_PWD__/${KEYSTONE_NEUTRON_PWD}/g" /etc/stackube/openstack/neutron-server/neutron_lbaas.conf

cp -f ${OS_CACERT} /etc/stackube/openstack/neutron-server/haproxy-ca.crt
docker run -it --net host  \
    --name stackube_bootstrap_neutron  \
    -v /etc/stackube/openstack/neutron-server/:/var/lib/kolla/config_files/:ro  \
    -v /var/log/stackube/openstack:/var/log/kolla/:rw  \
    -e "KOLLA_BOOTSTRAP="  \
    -e "KOLLA_CONFIG_STRATEGY=COPY_ALWAYS" \
    kolla/centos-binary-neutron-server:4.0.0

sleep 2
docker rm stackube_bootstrap_neutron


# bootstrap_service - Running Neutron lbaas bootstrap container
cp -f /etc/stackube/openstack/neutron-server/{neutron.conf,neutron_lbaas.conf,ml2_conf.ini,haproxy-ca.crt} \
      /etc/stackube/openstack/neutron-lbaas-agent/

docker run -it --net host  \
    --name stackube_bootstrap_neutron_lbaas_agent  \
    -v /etc/stackube/openstack/neutron-lbaas-agent/:/var/lib/kolla/config_files/:ro  \
    -v /var/log/stackube/openstack:/var/log/kolla/:rw  \
    -v /run/netns/:/run/netns/:shared  \
    -v /run:/run:shared  \
    \
    -e "KOLLA_BOOTSTRAP="  \
    -e "KOLLA_CONFIG_STRATEGY=COPY_ALWAYS" \
    \
    --privileged  \
    kolla/centos-binary-neutron-lbaas-agent:4.0.0

sleep 2
docker rm stackube_bootstrap_neutron_lbaas_agent


## start_container - neutron-server
docker run -d  --net host  \
    --name stackube_neutron_server  \
    -v /etc/stackube/openstack/neutron-server/:/var/lib/kolla/config_files/:ro  \
    -v /var/log/stackube/openstack:/var/log/kolla/:rw  \
    \
    -e "KOLLA_SERVICE_NAME=neutron-server"  \
    -e "KOLLA_CONFIG_STRATEGY=COPY_ALWAYS" \
    \
    --restart unless-stopped \
    kolla/centos-binary-neutron-server:4.0.0


## start_container - neutron-openvswitch-agent
cp -f /etc/stackube/openstack/neutron-server/{neutron.conf,ml2_conf.ini,haproxy-ca.crt} \
      /etc/stackube/openstack/neutron-openvswitch-agent/

docker run -d  --net host  \
    --name stackube_neutron_openvswitch_agent  \
    -v /etc/stackube/openstack/neutron-openvswitch-agent/:/var/lib/kolla/config_files/:ro  \
    -v /var/log/stackube/openstack:/var/log/kolla/:rw  \
    -v /run:/run:shared  \
    -v /lib/modules:/lib/modules:ro  \
    \
    -e "KOLLA_SERVICE_NAME=neutron-openvswitch-agent"  \
    -e "KOLLA_CONFIG_STRATEGY=COPY_ALWAYS" \
    \
    --restart unless-stopped \
    --privileged  \
    kolla/centos-binary-neutron-openvswitch-agent:4.0.0


## start_container - neutron-l3-agent
cp -f /etc/stackube/openstack/neutron-server/{neutron.conf,ml2_conf.ini,haproxy-ca.crt} \
      /etc/stackube/openstack/neutron-l3-agent/

docker run -d  --net host  \
    --name stackube_neutron_l3_agent  \
    -v /etc/stackube/openstack/neutron-l3-agent/:/var/lib/kolla/config_files/:ro  \
    -v /var/log/stackube/openstack:/var/log/kolla/:rw  \
    -v /run:/run:shared  \
    \
    -e "KOLLA_SERVICE_NAME=neutron-l3-agent"  \
    -e "KOLLA_CONFIG_STRATEGY=COPY_ALWAYS" \
    \
    --restart unless-stopped \
    --privileged  \
    kolla/centos-binary-neutron-l3-agent:4.0.0


## start_container - neutron-dhcp-agent
cp -f /etc/stackube/openstack/neutron-server/{neutron.conf,ml2_conf.ini,haproxy-ca.crt} \
      /etc/stackube/openstack/neutron-dhcp-agent/

docker run -d  --net host  \
    --name stackube_neutron_dhcp_agent  \
    -v /etc/stackube/openstack/neutron-dhcp-agent/:/var/lib/kolla/config_files/:ro  \
    -v /var/log/stackube/openstack:/var/log/kolla/:rw  \
    -v /run:/run:shared  \
    \
    -e "KOLLA_SERVICE_NAME=neutron-dhcp-agent"  \
    -e "KOLLA_CONFIG_STRATEGY=COPY_ALWAYS" \
    \
    --restart unless-stopped \
    --privileged  \
    kolla/centos-binary-neutron-dhcp-agent:4.0.0


## start_container - neutron-lbaas-agent
docker run -d  --net host  \
    --name stackube_neutron_lbaas_agent  \
    -v /etc/stackube/openstack/neutron-lbaas-agent/:/var/lib/kolla/config_files/:ro  \
    -v /var/log/stackube/openstack:/var/log/kolla/:rw  \
    -v /run/netns/:/run/netns/:shared  \
    -v /run:/run:shared  \
    \
    -e "KOLLA_SERVICE_NAME=neutron-lbaas-agent"  \
    -e "KOLLA_CONFIG_STRATEGY=COPY_ALWAYS" \
    \
    --restart unless-stopped \
    --privileged  \
    kolla/centos-binary-neutron-lbaas-agent:4.0.0


exit 0
