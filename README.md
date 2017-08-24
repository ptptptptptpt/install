# Stackube 多节点部署（无HA）

### 控制节点（1台）
- 要求
    - 1个公网网卡，带公网ip
    - 1个私网网卡，mtu >= 1600，与其它节点私网ip互通

### 计算节点（至少1台）
- 要求
    - 1个私网网卡，mtu >= 1600，与其它节点私网ip互通

### 网络节点（1台）
- 要求
    - 1个公网网卡，不带公网ip，作为 neutron external interface
    - 1个私网网卡，mtu >= 1600，与其它节点私网ip互通

### 存储节点（至少1台）
- 要求
    - 1个私网网卡，mtu >= 1600，与其它节点私网ip互通

### 公网ip池
- 要求
    - 若干数量的公网ip



SSH to the machine
Become root (e.g. sudo su -)

所有节点私网网卡 mtu 相同


在 控制节点 上执行 install （控制组件无需scp）

控制节点有所有节点的 ssh key

每个节点都要检查 os 版本，安装docker， run kolla-toolbox


hostname 应与 私网ip 还是 公网ip 对应？
