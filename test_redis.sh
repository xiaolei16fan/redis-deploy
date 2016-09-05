#!/bin/bash
#author xiaolei <xiaolei@16fan.com>
#date 2016.09.05
#这个脚本测试redis sentinel的功能

# 启动3台服务器的redis
service sentinel start
ssh root@192.168.33.15
service redis start
service sentinel start
echo "STATUS:"
ps -ef | grep redis

ssh root@192.168.33.16
service redis start
service sentinel start
echo "STATUS:"
ps -ef | grep redis

# 测试主从切换
redis-cli -p 26379 -h localhost sentinel failover mymaster
redis-cli -p 26379 -h localhost info | tail -1

# 压力测试

# 主从同步测试
redis-cli -p 6379 -h redisserver16fan set test test
redis-cli -p 6379 -h 192.168.33.16 get test