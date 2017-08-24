#!/bin/bash
#

programDir=`dirname $0`
programDir=$(readlink -f $programDir)
parentDir="$(dirname $programDir)"
programDirBaseName=$(basename $programDir)

set -x


export KUBECONFIG=/etc/kubernetes/admin.conf
aaa=`kubectl get csr --all-namespaces | grep Pending | awk '{print $1}'`
if [ "$aaa" ]; then
    for i in $aaa; do
        kubectl certificate approve $i || exit 1
    done
fi


exit 0
