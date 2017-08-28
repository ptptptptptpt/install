#!/bin/bash
#

programDir=`dirname $0`
programDir=$(readlink -f $programDir)
parentDir="$(dirname $programDir)"
programDirBaseName=$(basename $programDir)

set -x

kubeadm reset  || exit 1

systemctl stop hyperd kubelet
yum remove -y  kubelet  kubeadm  kubectl  qemu-hyper  hyperstart  hyper-container  || exit 1
rm -fr  /etc/kubernetes  /var/lib/kubelet  /var/run/kubernetes

systemctl stop frakti
rm -f  /usr/bin/frakti  /lib/systemd/system/frakti.service  || exit 1
systemctl daemon-reload



exit 0

