#!/bin/bash
#
# Dependencies:
#
# - ``OVSDB_IP``, ``ML2_LOCAL_IP``
# - ``KEYSTONE_API_IP``, ``KEYSTONE_NEUTRON_PWD`` must be defined
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


# bootstrap_service - Running Neutron lbaas bootstrap container
sed -i "s/__OVSDB_IP__/${OVSDB_IP}/g" /etc/stackube/openstack/neutron-lbaas-agent/ml2_conf.ini
sed -i "s/__LOCAL_IP__/${ML2_LOCAL_IP}/g" /etc/stackube/openstack/neutron-lbaas-agent/ml2_conf.ini

sed -i "s/__KEYSTONE_API_IP__/${KEYSTONE_API_IP}/g" /etc/stackube/openstack/neutron-lbaas-agent/neutron_lbaas.conf
sed -i "s/__NEUTRON_KEYSTONE_PWD__/${KEYSTONE_NEUTRON_PWD}/g" /etc/stackube/openstack/neutron-lbaas-agent/neutron_lbaas.conf

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
