#!/bin/bash
#author: xiaolei <xiaolei@16fan.com>
#date: 2016.09.05
#服务器D的redis配置脚本（Slave）

# 配置参数（在运行脚本之前先修改以下参数）
BIND_IP=192.168.33.11 # 填写本机IP
MASTER_IP=192.168.33.11 # 填写主Reis的IP

# 安装基本环境
yum -y install tcl gcc cc wget

# 检查安装目录
INSTALL_PATH="/root/redis-deploy"
CURRENT_PATH=`pwd .`
if [ $INSTALL_PATH = $CURRENT_PATH ]; then
    echo "[ENV CHECK]: installing path check successed."
else
    echo "[ERROR]: installing path check failed!"
    echo "please remove redis installing package to '/root' path."
    exit
fi

# 检查是否存在redis包文件，并开始安装redis
REDIS_URL=http://download.redis.io/releases/redis-3.2.3.tar.gz
REDIS_ARCHIVE="redis-3.2.3.tar.gz"
REDIS_SOURCE="redis-3.2.3"
test -f $INSTALL_PATH/$REDIS_ARCHIVE || wget $REDIS_URL

echo "Discovered $REDIS_ARCHIVE file, starting to install..."
tar -vxzf $REDIS_ARCHIVE

echo "switch to $REDIS_SOURCE path..."
cd $REDIS_SOURCE

# 修改测试代码，防止某些连接测试超时
sed -i "s/after 1000/after 10000/g" ./tests/integration/replication-2.tcl
sed -i "s/after 100/after 300/g" ./tests/integration/replication-psync.tcl

# 修改内存相关参数
KERNEL_MM_PATH=/sys/kernel/mm/transparent_hugepage/enabled

# Transparent Huge Pages (THP) 参数说明，来源（http://www.aichengxu.com/view/11064549），这是一个关于透明内存巨页的话题。
# 简单来说内存可管理的最小单位是page，一个page通常是4kb，那1M内存就有256个page，
# cpu通过内置的内存管理单元管理page表记录。Huge Page表示page的大小超过了4kb，
# 一般是2M到1G，它的出现主要是为了管理超大内存。比如1TB的内存。而THP就是管理Huge Pages
# 抽象层次，根据一些资料显示THP会导致内存锁影响性能，所以一般建议关闭。
# 主要参数有：
#   always 尽量使用透明内存，扫描内存，有521个4k页面可以整合，就整合成2M的页面
#   never 关闭，不使用透明内存
#   madvise 避免改变内存占用
grep 'transparent_hugepage' $KERNEL_MM_PATH || echo never > $KERNEL_MM_PATH # 关闭透明内存，提高内存性能，默认值为always
echo 'echo never > /sys/kernel/mm/transparent_hugepage/enabled' >> /etc/rc.local # 加入开机脚本
SYSCTL=/etc/sysctl.conf

# vm.overcommit_memory 参数说明，来源（http://www.aichengxu.com/view/11064549）
# 参数 0 表示检查是否有足够的内存可用，如果是，允许分配；如果内存不够，拒绝该请求，并返回一个错误给程序
# 参数 1 表示允许分配超出物理内存加上交换内存的请求
# 参数 2 表示总是返回 true
# 以下参数的修改主要是应付内存不够的情况
grep '^vm\.overcommit_memory\s*=\s*1$' $SYSCTL || echo 'vm.overcommit_memory = 1' >> $SYSCTL # 将过量使用内存参数设置为1，表示允许分配超出物理内存加上交换内存的请求

# net.core.somaxconn和net.ipv4.tcp_max_syn_backlog参数说明，来源（http://www.aichengxu.com/view/11064549）
# 修改网络连接的队列大小，对应了配置文件redis.conf中的“tcp-backlog 511”配置项，表示在
# 高并发下的最大队列大小，受限于系统的somaxconn与tcp_max_syn_backlog这两个值，所以应该把
# 这两个内核参数调大。
grep '^net\.core\.somaxconn\s*=\s*65535$' $SYSCTL || echo 'net.core.somaxconn = 65535' >> $SYSCTL # 最大队列长度，应付突发的大并发请求，默认为128
grep '^net\.ipv4\.tcp_max_syn_backlog\s*=\s*20480$' $SYSCTL || echo 'net.ipv4.tcp_max_syn_backlog = 20480' >> $SYSCTL # 半连接队列长度，此值受限于内存大小，默认为1024

# 使对/etc/sysctl.conf的修改生效
sysctl -p

# 修改redis可打开的最大文件数
# 参数说明：
# 如果redis报max number of clients错误，那么可以检查redis.conf的maxclients参数，redis默认将
# 这个参数设置为10000，也就是说默认可以承载10000的每秒并发量，如果超过这个数就会报错。如果
# maxclients设置为10000，而/etc/security/limits.conf的相应设置小于10000，那么会以limits.conf里的
# 设置来作为 maxclients的参数。以下命令就是修改系统最大文件描述符数。
SEC_LIMITS=/etc/security/limits.conf
grep '^\*\s*soft\s*nofile\s*65535$' $SEC_LIMITS || echo '*  soft nofile 65535' >> /etc/security/limits.conf
grep '^\*\s*soft\s*nofile\s*65535$' $SEC_LIMITS || echo '*  hard nofile 65535' >> /etc/security/limits.conf
PAM_FILE="/etc/pam.d/sudo /etc/pam.d/common-session-noninteractive"
for pam in $PAM_FILE; do
    if [ -f $pam ] && grep 'pam_limits.so' $pam; then
        echo "maximum open files already set to 65535."
    else
        echo "$pam file does not exists or it does not include pam_limits.so record."
    fi
done

echo "set PREFIX=/usr/local/redis and make..."
make PREFIX=/usr/local/redis install

echo "make test && make install..."
make test && make install

echo "make some path in /usr/local/redis..."
mkdir /usr/local/redis/{conf,log,script,data,run}

echo "copy some configuration file to /usr/local/redis/conf..."
cp redis.conf sentinel.conf /usr/local/redis/conf

# 测试安装情况
echo "STARTING to TEST redis status..."
echo "[1] checking redis path installed on /usr/local/redis..."
REDIS_PATH=/usr/local/redis
TEST_DIR="conf log script data"
for dir in $TEST_DIR; do
    if [ -d $REDIS_PATH/$dir ]; then
        echo "[1] $REDIS_PATH/$dir passed!"
    else
        echo "[1] $REDIS_PATH/$dir failed!"
    fi
done

echo "[2] checking files in redis bin path..."
BIN_FILE="redis-benchmark redis-check-aof redis-check-rdb redis-cli redis-sentinel redis-server"
for file in $BIN_FILE; do
    if [ -f $REDIS_PATH/bin/$file ]; then
        echo "[2] $REDIS_PATH/bin/$file passed!"
    else
        echo "[2] $REDIS_PATH/bin/$file faild!"
    fi
done

echo "[3] checking configuration files wethere exists..."
CONF_FILE="redis.conf sentinel.conf"
for conf in $CONF_FILE; do
    if [ -f $REDIS_PATH/conf/$conf ]; then
        echo "[3] $REDIS_PATH/conf/$conf passed!"
    else
        echo "[3] $REDIS_PATH/conf/$conf failed!"
    fi
done
echo "INSTALLING REDIS SUCCESSED!"

read -p "Is this ok? Then press ENTER to go on or Ctrl-C to abort." _UNUSED_

# 修改配置文件redis.conf
REDIS_CONF=/usr/local/redis/conf
sed -i "s/^bind\s*127\.0\.0\.1$/bind 127.0.0.1 $BIND_IP/g" $REDIS_CONF/redis.conf
sed -i "s/^daemonize\s*no$/daemonize yes/g" $REDIS_CONF/redis.conf
sed -i "s/^slave-priority\s*[0-9]*$/slave-priority 100/g" $REDIS_CONF/redis.conf
grep '^maxmemory\s*[0-9A-Za-z]*$' $REDIS_CONF/redis.conf || echo "maxmemory 8gb" >> $REDIS_CONF/redis.conf
sed -i "s/^dir\s*\.\/$/dir \/usr\/local\/redis\/data/g" $REDIS_CONF/redis.conf
sed -i "s/^logfile\s*\"*$/logfile \/usr\/local\/redis\/log\/redis.log/g" $REDIS_CONF/redis.conf
sed -i "s/^pidfile\s*\/var\/run\/redis_6379\.pid/pidfile \/usr\/local\/redis\/run\/redis.pid/g" $REDIS_CONF/redis.conf
sed -i "s/^save\s/# save/g" $REDIS_CONF/redis.conf
sed -i "s/^tcp-backlog 511/tcp-backlog 65535/g" $REDIS_CONF/redis.conf
grep '^slaveof.*' $REDIS_CONF/redis.conf || echo "slaveof $MASTER_IP 6379" >> $REDIS_CONF/redis.conf
grep '^maxclients.*' $REDIS_CONF/redis.conf || echo "maxclients 65535" >> $REDIS_CONF/redis.conf
sed -i "s/^timeout\s0/timeout 30/g" $REDIS_CONF/redis.conf

# 测试配置
echo "======================redis.conf==========================="
grep -v '^#' $REDIS_CONF/redis.conf | grep -v '^$'


# 修改配置文件sentinel.conf
sed -i "s/^bind\s*127\.0\.0\.1$/bind 127.0.0.1 $BIND_IP/g" $REDIS_CONF/sentinel.conf
grep '^bind.*' $REDIS_CONF/sentinel.conf || echo "bind $BIND_IP" >> $REDIS_CONF/sentinel.conf
sed -i "s/^daemonize\s*no$/daemonize yes/g" $REDIS_CONF/sentinel.conf
grep '^daemonize.*' $REDIS_CONF/sentinel.conf || echo "daemonize yes" >> $REDIS_CONF/sentinel.conf
sed -i "s/^logfile\s*\"*$/logfile \/usr\/local\/redis\/log\/sentinel.log/g" $REDIS_CONF/sentinel.conf
grep '^logfile.*' $REDIS_CONF/sentinel.conf || echo "logfile /usr/local/redis/log/sentinel.log" >> $REDIS_CONF/sentinel.conf
sed -i "s/^pidfile\s*\/var\/run\/redis_6379\.pid/pidfile \/usr\/local\/redis\/run\/sentinel.pid/g" $REDIS_CONF/sentinel.conf
grep '^pidfile.*' $REDIS_CONF/sentinel.conf || echo "pidfile /usr/local/redis/run/sentinel.pid" >> $REDIS_CONF/sentinel.conf
sed -i "s/^sentinel\smonitor.*/sentinel monitor mymaster $MASTER_IP 6379 2/g" $REDIS_CONF/sentinel.conf
sed -i "s/^sentinel\sdown-after-milliseconds.*/sentinel down-after-milliseconds mymaster 5000/g" $REDIS_CONF/sentinel.conf
sed -i "s/^sentinel\sfailover-timeout.*/sentinel failover-timeout mymaster 60000/g" $REDIS_CONF/sentinel.conf


# 测试配置
echo "======================sentinel.conf==========================="
grep -v '^#' $REDIS_CONF/sentinel.conf | grep -v '^$'
echo
read -p "Is this ok? Then press ENTER to go on or Ctrl-C to abort." _UNUSED_

# 配置开机启动redis
REDIS_INIT_PATH=/etc/init.d/redis
cp ./utils/redis_init_script $REDIS_INIT_PATH
sed -i "2a #\ chkconfig:\ 2345\ 90\ 10" $REDIS_INIT_PATH
sed -i "s/^EXEC.*/EXEC=\/usr\/local\/redis\/bin\/redis-server/g" $REDIS_INIT_PATH
sed -i "s/^CLIEXEC.*/CLIEXEC=\/usr\/local\/redis\/bin\/redis-cli/g" $REDIS_INIT_PATH
sed -i "s/^PIDFILE.*/PIDFILE=\/usr\/local\/redis\/run\/redis.pid/g" $REDIS_INIT_PATH
sed -i "s/^CONF.*/CONF=\/usr\/local\/redis\/conf\/redis.conf/g" $REDIS_INIT_PATH


# 配置开机启动sentinel
SENTINEL_INIT_PATH=/etc/init.d/sentinel 
cp ./utils/redis_init_script $SENTINEL_INIT_PATH
sed -i "2a #\ chkconfig:\ 2345\ 90\ 10" $SENTINEL_INIT_PATH
sed -i "s/^EXEC.*/EXEC=\/usr\/local\/redis\/bin\/redis-sentinel/g" $SENTINEL_INIT_PATH
sed -i "s/^CLIEXEC.*/CLIEXEC=\/usr\/local\/redis\/bin\/redis-cli/g" $SENTINEL_INIT_PATH
sed -i "s/^PIDFILE.*/PIDFILE=\/usr\/local\/redis\/run\/sentinel.pid/g" $SENTINEL_INIT_PATH
sed -i "s/^CONF.*/CONF=\/usr\/local\/redis\/conf\/sentinel.conf/g" $SENTINEL_INIT_PATH
sed -i "s/Redis/Sentinel/g" $SENTINEL_INIT_PATH

# 加入开机启动
chkconfig redis on
chkconfig sentinel on
grep '/usr/local/redis/bin' /etc/profile || echo 'export PATH="$PATH:/usr/local/redis/bin"' >> /etc/profile
source /etc/profile

# 测试开机启动
service redis start
if [ `echo $?` != 0 ]; then
    echo "Cannot lunch this redis server. Please manually execute [service redis start] commands to start."
    exit 1
fi
sleep 2
service sentinel start
if [ `echo $?` != 0 ]; then
    echo "Cannot lunch this sentinel server. Please manually execute [service sentinel start] commands to start."
    exit 1
fi
sleep 2
REDIS_PID_PATH=/usr/local/redis/run
if [ -f $REDIS_PID_PATH/redis.pid ]; then
    echo "OK! REDIS IS RUNNING..."
    cat $REDIS_PID_PATH/redis.pid
else
    echo "$REDIS_PID_PATH/redis.pid does not exists."
fi
sleep 2
if [ -f $REDIS_PID_PATH/sentinel.pid ]; then
    echo "OK! SENTINEL IS RUNNING..."
    cat $REDIS_PID_PATH/sentinel.pid
else
    echo "$REDIS_PID_PATH/sentinel.pid does not exists."
fi
ps -ef | grep 'redis'
# redis-cli -p 6379 shutdown && echo "shut down redis server..."
# redis-cli -p 26379 -h $BIND_IP shutdown && echo "shut down sentinel server..."
if [ `echo $?` = 0 ]; then
    echo "OK! REDIS AND SENTINEL CAN WORK ON THIS SERVER."
fi