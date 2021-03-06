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

[ "${CONTROL_NODE_PRIVATE_IP}" ]
[ "${STORAGE_NODES_PRIVATE_IP}" ]
[ "${STORAGE_NODES_CEPH_OSD_DATA_DIR}" ]


# ceph-mon
export CEPH_MON_PUBLIC_IP="${CONTROL_NODE_PRIVATE_IP}"
export CEPH_FSID=${CEPH_FSID:-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}
/bin/bash ${programDir}/ceph/deploy_ceph_mon.sh


# ceph-osd
storageIpList=(`echo "${STORAGE_NODES_PRIVATE_IP}" | sed -e 's/,/\n/g'`)
osdDataDirList=(`echo "${STORAGE_NODES_CEPH_OSD_DATA_DIR}" | sed -e 's/,/\n/g'`)
[ ${#storageIpList[@]} -eq ${#osdDataDirList[@]} ]

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



