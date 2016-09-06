#!/bin/bash
#author xiaolei <xiaolei@16fan.com>
#date 2016.09.05
#在发生主从切换时，将管理主机（SERVER_A）的HOSTS修改为最新 redis master 的IP

MASTER_IP=${6}
DEFAULT_MASTER=192.168.33.11

if [ ! `grep 'redisserver16fan' /etc/hosts` ]; then
        echo "${DEFAULT_MASTER} redisserver16fan" >> /etc/hosts 
else
        sed -i '/redisserver16fan/d' /etc/hosts
        echo "${MASTER_IP} redisserver16fan" >> /etc/hosts
fi

# 通知管理员
EMAIL=xiaolei@16fan.com
date=`date +%Y/%m/%d-%H:%M:%S`
issues=/usr/local/redis/log/redis_issues.log
echo -e "FAILOVER EVENT EXCEPTION at  ${date} \nSwitch HOST from: ${4} to: ${6}\nCURRENT MASTER: ${6}" > $issues
cat $issues  | mail  -s "Redis Failover Notice!" $EMAIL