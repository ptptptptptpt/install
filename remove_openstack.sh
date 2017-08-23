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

## clean certificates
source ${programDir}/lib_tls.sh
cleanup_CA


## remove docker containers
stackubeConstaners=`docker ps -a | awk '{print $NF}' | grep '^stackube_openstack_' `
if [ "${stackubeConstaners}" ]; then
    docker rm -f $stackubeConstaners
fi

## rm dirs
rm -fr /etc/stackube/openstack  /var/log/stackube/openstack  /var/lib/stackube/openstack



exit 0

