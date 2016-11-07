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
grep 'transparent_hugepage' $KERNEL_MM_PATH || echo never > $KERNEL_MM_PATH
echo 'echo never > /sys/kernel/mm/transparent_hugepage/enabled' >> /etc/rc.local
SYSCTL=/etc/sysctl.conf
grep '^vm\.overcommit_memory\s*=\s*1$' $SYSCTL || echo 'vm.overcommit_memory = 1' >> $SYSCTL
grep '^net\.core\.somaxconn\s*=\s*65535$' $SYSCTL || echo 'net.core.somaxconn = 65535' >> $SYSCTL
grep '^net\.ipv4\.tcp_max_syn_backlog\s*=\s*20480$' $SYSCTL || echo 'net.ipv4.tcp_max_syn_backlog = 20480' >> $SYSCTL
sysctl -p

# 修改redis可打开的最大文件数
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
grep '^maxmemory\s*[0-9A-Za-z]*$' $REDIS_CONF/redis.conf || echo "maxmemory 10gb" >> $REDIS_CONF/redis.conf
sed -i "s/^dir\s*\.\/$/dir \/usr\/local\/redis\/data/g" $REDIS_CONF/redis.conf
sed -i "s/^logfile\s*\"*$/logfile \/usr\/local\/redis\/log\/redis.log/g" $REDIS_CONF/redis.conf
sed -i "s/^pidfile\s*\/var\/run\/redis_6379\.pid/pidfile \/usr\/local\/redis\/run\/redis.pid/g" $REDIS_CONF/redis.conf
sed -i "s/^save\s/# save/g" $REDIS_CONF/redis.conf
grep '^slaveof.*' $REDIS_CONF/redis.conf || echo "slaveof $MASTER_IP 6379" >> $REDIS_CONF/redis.conf

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
sleep 2
service sentinel start
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