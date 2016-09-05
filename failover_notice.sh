#!/bin/bash
#author xiaolei <xiaolei@16fan.com>
#date 2016.09.05
#当发生主从切换时通知管理员

EMAIL=xiaolei@16fan.com
echo "master failover at `date +%Y/%m/%d-%H:%M:%S` " > /usr/local/redis/log/redis_issues.log
cat /usr/local/redis/log/redis_issues.log | mail  -s "Redis Failover Caution!!!" $EMAIL