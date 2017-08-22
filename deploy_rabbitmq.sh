#!/bin/bash
#
# Dependencies:
#
# - ``RABBITMQ_PWD`` must be defined
#

programDir=`dirname $0`
programDir=$(readlink -f $programDir)
parentDir="$(dirname $programDir)"
programDirBaseName=$(basename $programDir)

set -x

## rabbitmq 
mkdir -p /var/lib/stackube/openstack/rabbitmq  && \
docker run -d \
    --name stackube_rabbitmq \
    --net host  \
    -v /var/lib/stackube/openstack/rabbitmq:/var/lib/rabbitmq \
    --restart unless-stopped \
    rabbitmq:3.6 || exit 1

sleep 5
for i in 1 2 3 4 5; do
    docker exec -it stackube_rabbitmq rabbitmqctl status && break
    sleep $i
done
sleep 5

docker exec -it stackube_rabbitmq rabbitmqctl add_user openstack ${RABBITMQ_PWD} || exit 1
docker exec -it stackube_rabbitmq rabbitmqctl set_permissions openstack ".*" ".*" ".*" || exit 1

exit 0