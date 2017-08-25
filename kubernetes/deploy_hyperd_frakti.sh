#!/bin/bash
#
# Dependencies:
#
# - ``KUBERNETES_API_PRIVATE_IP``
# - ``FRAKTI_VERSION``  must be defined
#

programDir=`dirname $0`
programDir=$(readlink -f $programDir)
parentDir="$(dirname $programDir)"
programDirBaseName=$(basename $programDir)

set -o errexit
set -o nounset
set -o pipefail
set -x


## install libvirtd
yum install -y libvirt


## install hyperd
CENTOS7_QEMU_HYPER="qemu-hyper-2.4.1-3.el7.centos.x86_64"
CENTOS7_HYPERSTART="hyperstart-0.8.1-1.el7.centos.x86_64"
CENTOS7_HYPER="hyper-container-0.8.1-1.el7.centos.x86_64"

set +e
/bin/bash -c "ping -c 3 -W 2 hypercontainer-install.s3.amazonaws.com >/dev/null 2>&1"
if [[ $? -ne 0 ]];then
    S3_URL="http://mirror-hypercontainer-install.s3.amazonaws.com"
else
    S3_URL="http://hypercontainer-install.s3.amazonaws.com"
fi
set -e

yum install -y ${S3_URL}/${CENTOS7_QEMU_HYPER}.rpm ${S3_URL}/${CENTOS7_HYPERSTART}.rpm ${S3_URL}/${CENTOS7_HYPER}.rpm

cat > /etc/hyper/config << EOF
Kernel=/var/lib/hyper/kernel
Initrd=/var/lib/hyper/hyper-initrd.img
Hypervisor=qemu
StorageDriver=overlay
gRPCHost=127.0.0.1:22318

EOF


## install frakti
curl -sSL https://github.com/kubernetes/frakti/releases/download/${FRAKTI_VERSION}/frakti -o /usr/bin/frakti 
chmod +x /usr/bin/frakti 

dockerInfo=`docker info `
cgroup_driver=`echo "${dockerInfo}" | awk '/Cgroup Driver/{print $3}' `
[ "${cgroup_driver}" ]

echo "[Unit]
Description=Hypervisor-based container runtime for Kubernetes
Documentation=https://github.com/kubernetes/frakti
After=network.target
[Service]
ExecStart=/usr/bin/frakti --v=3 \
          --log-dir=/var/log/frakti \
          --logtostderr=false \
          --cgroup-driver=${cgroup_driver} \
          --listen=/var/run/frakti.sock \
          --streaming-server-addr=${KUBERNETES_API_PRIVATE_IP} \
          --hyper-endpoint=127.0.0.1:22318
MountFlags=shared
#TasksMax=8192
LimitNOFILE=1048576
LimitNPROC=1048576
LimitCORE=infinity
TimeoutStartSec=0
Restart=on-abnormal
[Install]
WantedBy=multi-user.target
"  > /lib/systemd/system/frakti.service 


## start services
systemctl daemon-reload
systemctl enable hyperd frakti libvirtd
systemctl restart hyperd libvirtd
sleep 3
systemctl restart frakti
sleep 10

## check
hyperctl list 
pgrep -f '/usr/bin/frakti' 
[ -e /var/run/frakti.sock ] 



exit 0
