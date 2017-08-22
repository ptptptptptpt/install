#!/bin/bash
#
# Dependencies:
#
# - ``API_IP`` must be defined
#

programDir=`dirname $0`
programDir=$(readlink -f $programDir)
parentDir="$(dirname $programDir)"
programDirBaseName=$(basename $programDir)

set -o errexit
set -o nounset
set -o pipefail
set -x


## make certificates
HOST_IP=${API_IP}
SERVICE_HOST=${API_IP}
SERVICE_IP=${API_IP}
source ${programDir}/lib_tls.sh
DATA_DIR='/etc/stackube/openstack/certificates'
mkdir -p ${DATA_DIR}
init_CA
init_cert


## log dir
mkdir -p /var/log/stackube/openstack
chmod 777 /var/log/stackube/openstack


## config files
mkdir -p /etc/stackube/openstack
cp -a ${programDir}/config_openstack/haproxy /etc/stackube/openstack/
sed -i "s/__API_IP__/${API_IP}/g" /etc/stackube/openstack/haproxy/haproxy.cfg
# STACKUBE_CERT defined in lib_tls.sh
cat ${STACKUBE_CERT} > /etc/stackube/openstack/haproxy/haproxy.pem


## run
docker run -d  --net host  \
    --name stackube_haproxy  \
    -v /etc/stackube/openstack/haproxy/:/var/lib/kolla/config_files/:ro  \
    -v /var/log/stackube/openstack:/var/log/kolla/:rw  \
    \
    -e "KOLLA_SERVICE_NAME=haproxy"  \
    -e "KOLLA_CONFIG_STRATEGY=COPY_ALWAYS" \
    \
    --restart unless-stopped \
    --privileged  \
    kolla/centos-binary-haproxy:4.0.0


exit 0

