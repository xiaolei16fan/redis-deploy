#!/bin/bash
#author xiaolei <xiaolei@16fan.com>
#date 2016.09.05
#这个脚本测试redis sentinel的功能

# 测试主从切换
SERVER_A_IP=192.168.33.14
echo "FAILOVER testing..."
redis-cli -p 26379 -h $SERVER_A_IP sentinel failover mymaster
redis-cli -p 26379 -h $SERVER_A_IP info | tail -1
echo "FAILOVER test success!"

# 压力测试

# 主从同步测试
echo "SET value to redis master..."
redis-cli -p 6379 -h redisserver16fan set test test
echo "GET value from redis slave..."
redis-cli -p 6379 -h 192.168.33.15 get test
echo "SYNC test success!"