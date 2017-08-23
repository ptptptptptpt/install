#!/bin/bash
#

programDir=`dirname $0`
programDir=$(readlink -f $programDir)
parentDir="$(dirname $programDir)"
programDirBaseName=$(basename $programDir)

set -o errexit
set -o nounset
set -o pipefail
set -x


## remove docker containers
stackubeCephConstaners=`docker ps -a | awk '{print $NF}' | grep '^stackube_ceph_' `
if [ "${stackubeCephConstaners}" ]; then
    docker rm -f $stackubeCephConstaners
fi

## rm dirs
rm -fr /etc/stackube/ceph  /var/log/stackube/ceph  /var/lib/stackube/ceph



exit 0

