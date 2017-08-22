#!/bin/bash
#
# Dependencies:
#
# - ``OVSDB_IP``
# - ``OPENSTACK_ENDPOINT_IP``
# - ``RABBITMQ_HOST``, ``RABBITMQ_PWD``
# - ``MYSQL_HOST``, ``MYSQL_ROOT_PWD``
# - ``KEYSTONE_ADMIN_PWD``, ``NEUTRON_API_IP``
# - ``KEYSTONE_NEUTRON_PWD``, ``MYSQL_NEUTRON_PWD`` must be defined
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


## openvswitch-db-server
sed -i "s/__OVSDB_IP__/${OVSDB_IP}/g" /etc/stackube/openstack/openvswitch-db-server/config.json
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


## start_container - neutron-openvswitch-agent
sed -i "s/__OVSDB_IP__/${OVSDB_IP}/g" /etc/stackube/openstack/neutron-server/ml2_conf.ini
sed -i "s/__LOCAL_IP__/${ML2_LOCAL_IP}/g" /etc/stackube/openstack/neutron-server/ml2_conf.ini

sed -i "s/__RABBITMQ_HOST__/${RABBITMQ_HOST}/g" /etc/stackube/openstack/neutron-server/neutron.conf
sed -i "s/__RABBITMQ_PWD__/${RABBITMQ_PWD}/g" /etc/stackube/openstack/neutron-server/neutron.conf
sed -i "s/__NEUTRON_API_IP__/${NEUTRON_API_IP}/g" /etc/stackube/openstack/neutron-server/neutron.conf
sed -i "s/__MYSQL_HOST__/${MYSQL_HOST}/g" /etc/stackube/openstack/neutron-server/neutron.conf
sed -i "s/__OPENSTACK_ENDPOINT_IP__/${OPENSTACK_ENDPOINT_IP}/g" /etc/stackube/openstack/neutron-server/neutron.conf
sed -i "s/__NEUTRON_KEYSTONE_PWD__/${KEYSTONE_NEUTRON_PWD}/g" /etc/stackube/openstack/neutron-server/neutron.conf
sed -i "s/__MYSQL_NEUTRON_PWD__/${MYSQL_NEUTRON_PWD}/g" /etc/stackube/openstack/neutron-server/neutron.conf

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
    kolla/centos-binary-neutron-openvswitch-agent:4.0.0  || exit 1

exit 0
