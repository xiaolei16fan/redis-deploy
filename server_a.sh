#!/bin/bash
#author: xiaolei <xiaolei@16fan.com>
#date: 2016.09.01
#服务器A的redis配置脚本

# 配置参数（在运行脚本之前先修改以下参数）
BIND_IP=192.168.33.11 # 填写本机IP
MASTER_IP=192.168.33.11 # 填写主Reis的IP
EMAIL=xiaolei@16fan.com # 填写自己的邮箱
EMAIL_PASSWD=123456 # 填写自己的邮箱密码

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
echo 'echo never > /sys/kernel/mm/transparent_hugepage/enabled' >> /etc/rc.d/rc.local
cp /etc/sysctl.conf /etc/sysctl.conf.bak
SYSCTL=/etc/sysctl.conf
grep '^vm\.overcommit_memory\s*=\s*1$' $SYSCTL || echo 'vm.overcommit_memory = 1' >> $SYSCTL
grep '^net\.core\.somaxconn\s*=\s*65535$' $SYSCTL || echo 'net.core.somaxconn = 65535' >> $SYSCTL
grep '^net\.ipv4\.tcp_max_syn_backlog\s*=\s*20480$' $SYSCTL || echo 'net.ipv4.tcp_max_syn_backlog = 20480' >> $SYSCTL
sysctl -p

# 修改redis可打开的最大文件数
cp /etc/security/limits.conf /etc/security/limits.conf.bak
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
taskset -c 1 make test && make install

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

# 修改配置文件sentinel.conf
REDIS_CONF=/usr/local/redis/conf
grep '^bind.*' $REDIS_CONF/sentinel.conf || echo "bind $BIND_IP" >> $REDIS_CONF/sentinel.conf
grep '^daemonize.*' $REDIS_CONF/sentinel.conf || echo "daemonize yes" >> $REDIS_CONF/sentinel.conf
grep '^logfile.*' $REDIS_CONF/sentinel.conf || echo "logfile /usr/local/redis/log/sentinel.log" >> $REDIS_CONF/sentinel.conf
grep '^pidfile.*' $REDIS_CONF/sentinel.conf || echo "pidfile /usr/local/redis/run/sentinel.pid" >> $REDIS_CONF/sentinel.conf
sed -i "s/^sentinel\smonitor.*/sentinel monitor mymaster $MASTER_IP 6379 2/g" $REDIS_CONF/sentinel.conf
sed -i "s/^sentinel\sdown-after-milliseconds.*/sentinel down-after-milliseconds mymaster 5000/g" $REDIS_CONF/sentinel.conf
sed -i "s/^sentinel\sfailover-timeout.*/sentinel failover-timeout mymaster 60000/g" $REDIS_CONF/sentinel.conf
cp $INSTALL_PATH/bind_hosts.sh  /usr/local/redis/script
cp $INSTALL_PATH/warning_notice.sh /usr/local/redis/script
chmod +x /usr/local/redis/script/*
grep '^sentinel\s*client-reconfig-script.*' $REDIS_CONF/sentinel.conf || echo "sentinel client-reconfig-script mymaster /usr/local/redis/script/bind_hosts.sh" >> $REDIS_CONF/sentinel.conf
grep '^sentinel\s*notification-script.*' $REDIS_CONF/sentinel.conf || echo "sentinel notification-script mymaster /usr/local/redis/script/warning_notice.sh" >> $REDIS_CONF/sentinel.conf


# 测试配置
echo "======================sentinel.conf==========================="
grep -v '^#' $REDIS_CONF/sentinel.conf | grep -v '^$'
echo
read -p "Is this ok? Then press ENTER to go on or Ctrl-C to abort." _UNUSED_

# 邮件通知配置
yum -y install mailx sendmail
chkconfig sendmail on
service sendmail start
echo "Configuring /etc/mail.rc..."
sleep 2
grep '^set\s*from=.*' /etc/mail.rc || echo "set from=$EMAIL smtp=smtp.ym.163.com" >> /etc/mail.rc
grep '^set\s*smtp-auth-user.*' /etc/mail.rc || echo "set smtp-auth-user=$EMAIL smtp-auth-password=$EMAIL_PASSWD smtp-auth=login" >> /etc/mail.rc

# 邮件通知测试
echo "Email testing..."
echo "发生了一次主从切换！" | mail -s test $EMAIL
echo "Email testing end! Please check out your email box."

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
chkconfig sentinel on
grep '/usr/local/redis/bin' /etc/profile || echo 'export PATH="$PATH:/usr/local/redis/bin"' >> /etc/profile
source /etc/profile

# 测试开机启动
service sentinel start
if [ `echo $?` != 0 ]; then
    echo "Cannot lunch this sentinel server. Please manually execute [service sentinel start] commands to start."
    exit 1
fi
sleep 4
REDIS_PID_PATH=/usr/local/redis/run

if [ -f $REDIS_PID_PATH/sentinel.pid ]; then
    echo "OK! SENTINEL IS RUNNING..."
    cat $REDIS_PID_PATH/sentinel.pid
    ps -ef | grep 'sentinel'
else
    echo "$REDIS_PID_PATH/sentinel.pid does not exists."
fi
# redis-cli -p 26379 -h $BIND_IP shutdown && echo "shut down sentinel server..."
if [ `echo $?` = 0 ]; then
    echo "OK! REDIS AND SENTINEL CAN WORK ON THIS SERVER."
fi
