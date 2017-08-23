#!/bin/bash
#
# Dependencies:
#
# - ``CEPH_PUBLIC_IP``, ``CEPH_CLUSTER_IP``,
# - ``CEPH_FSID``,
# - ``CEPH_OSD_DATA_DIR``   must be defined
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
mkdir -p /var/log/stackube/ceph
chmod 777 /var/log/stackube/ceph

## config files
mkdir -p /etc/stackube/ceph
cp -a ${programDir}/config_ceph/keystone /etc/stackube/ceph/
sed -i "s/__FSID__/${CEPH_FSID}/g" /etc/stackube/ceph/ceph-mon/ceph.conf
sed -i "s/__PUBLIC_IP__/${CEPH_PUBLIC_IP}/g" /etc/stackube/ceph/ceph-mon/ceph.conf
sed -i "s/__PUBLIC_IP__/${CEPH_PUBLIC_IP}/g" /etc/stackube/ceph/ceph-mon/config.json

mkdir -p /var/lib/stackube/ceph/ceph_mon_config  && \
mkdir -p /var/lib/stackube/ceph/ceph_mon  && \
docker run --net host  \
    --name stackube_bootstrap_ceph_mon  \
    -v /etc/stackube/ceph/ceph-mon/:/var/lib/kolla/config_files/:ro  \
    -v /var/log/stackube/ceph:/var/log/kolla/:rw  \
    -v /var/lib/stackube/ceph/ceph_mon_config:/etc/ceph/:rw  \
    -v /var/lib/stackube/ceph/ceph_mon:/var/lib/ceph/:rw  \
    \
    -e "KOLLA_BOOTSTRAP="  \
    -e "KOLLA_CONFIG_STRATEGY=COPY_ALWAYS" \
    -e "MON_IP=${CEPH_PUBLIC_IP}" \
    -e "HOSTNAME=${CEPH_PUBLIC_IP}" \
    kolla/centos-binary-ceph-mon:4.0.0

docker rm stackube_bootstrap_ceph_mon

docker run -d  --net host  \
    --name stackube_ceph_mon  \
    -v /etc/stackube/ceph/ceph-mon/:/var/lib/kolla/config_files/:ro  \
    -v /var/log/stackube/ceph:/var/log/kolla/:rw  \
    -v /var/lib/stackube/ceph/ceph_mon_config:/etc/ceph/:rw  \
    -v /var/lib/stackube/ceph/ceph_mon:/var/lib/ceph/:rw  \
    \
    -e "KOLLA_SERVICE_NAME=ceph-mon"  \
    -e "HOSTNAME=${CEPH_PUBLIC_IP}"  \
    -e "KOLLA_CONFIG_STRATEGY=COPY_ALWAYS" \
    \
    --restart unless-stopped \
    kolla/centos-binary-ceph-mon:4.0.0

sleep 5

docker exec stackube_ceph_mon ceph -s


## ceph-osd
cp --remove-destination /var/lib/stackube/ceph/ceph_mon_config/{ceph.client.admin.keyring,ceph.conf} /etc/stackube/ceph/ceph-osd/ 
sed -i "s/__PUBLIC_IP__/${CEPH_PUBLIC_IP}/g" /etc/stackube/ceph/ceph-osd/add_osd.sh
sed -i "s/__PUBLIC_IP__/${CEPH_PUBLIC_IP}/g" /etc/stackube/ceph/ceph-osd/config.json
sed -i "s/__CLUSTER_IP__/${CEPH_CLUSTER_IP}/g" /etc/stackube/ceph/ceph-osd/config.json

mkdir -p ${CEPH_OSD_DATA_DIR}

docker run --net host  \
    --name stackube_bootstrap_ceph_osd  \
    -v /etc/stackube/ceph/ceph-osd/:/var/lib/kolla/config_files/:ro  \
    -v /var/log/stackube/ceph:/var/log/kolla/:rw  \
    -v ${CEPH_OSD_DATA_DIR}:/var/lib/ceph/:rw  \
    \
    kolla/centos-binary-ceph-osd:4.0.0 /bin/bash /var/lib/kolla/config_files/add_osd.sh 

docker rm stackube_bootstrap_ceph_osd

theOsd=`ls ${CEPH_OSD_DATA_DIR}/osd/ | grep -- 'ceph-' | head -n 1`
[ "${theOsd}" ]
osdId=`echo $theOsd | awk -F\- '{print $NF}'`
[ "${osdId}" ]

docker run -d  --net host  \
    --name stackube_ceph_osd_${osdId}  \
    -v /etc/stackube/ceph/ceph-osd/:/var/lib/kolla/config_files/:ro  \
    -v /var/log/stackube/ceph:/var/log/kolla/:rw  \
    -v ${CEPH_OSD_DATA_DIR}:/var/lib/ceph/:rw  \
    \
    -e "KOLLA_SERVICE_NAME=ceph-osd"  \
    -e "KOLLA_CONFIG_STRATEGY=COPY_ALWAYS" \
    -e "OSD_ID=${osdId}"  \
    -e "JOURNAL_PARTITION=/var/lib/ceph/osd/ceph-${osdId}/journal" \
    \
    --restart unless-stopped \
    kolla/centos-binary-ceph-osd:4.0.0

sleep 5

docker exec stackube_ceph_mon ceph osd crush tree


## host config
yum install ceph -y 
systemctl disable ceph.target ceph-mds.target ceph-mon.target ceph-osd.target
cp -f /var/lib/stackube/ceph/ceph_mon_config/* /etc/ceph/
ceph -s



exit 0
