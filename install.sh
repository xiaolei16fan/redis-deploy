#!/bin/bash
#author: xiaolei <xiaolei@16fan.com>
#date: 2016.09.01

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
wget $REDIS_URL
if [ -f $INSTALL_PATH/$REDIS_ARCHIVE ]; then
    
    echo "Discovered $REDIS_ARCHIVE file, starting to install..."
    tar -vxzf $REDIS_ARCHIVE
    
    echo "switch to $REDIS_SOURCE path..."
    cd $REDIS_SOURCE

    # 修改测试代码，防止某些连接测试超时
    sed -i "s/after 1000/after 10000/g" ./tests/integration/replication-2.tcl
    sed -i "s/after 100/after 300/g" ./tests/integration/replication-psync.tcl

    # 修改内存相关参数
    echo never > /sys/kernel/mm/transparent_hugepage/enabled
    echo 'echo never > /sys/kernel/mm/transparent_hugepage/enabled' >> /etc/rc.local
    $SYSCTL=/etc/sysctl.conf
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
    mkdir /usr/local/redis/{conf,log,script,data}

    echo "copy some configuration file to /usr/local/redis/conf..."
    cp redis.conf sentinel.conf /usr/local/redis/conf

    echo "installing redis successed!"
else
    echo "[ERROR]: $REDIS_ARCHIVE file did not found."
    exit
fi

read -p "Is this ok? Then press ENTER to go on or Ctrl-C to abort." _UNUSED_

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

read -p "Is this ok? Then press ENTER to go on or Ctrl-C to abort." _UNUSED_

# 修改配置文件