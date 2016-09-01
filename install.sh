#!/bin/bash
#author: xiaolei <xiaolei@16fan.com>
#date: 2016.09.01

# 安装基本环境
yum -y install tcl gcc cc

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