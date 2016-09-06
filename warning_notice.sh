#!/bin/bash
#author xiaolei <xiaolei@16fan.com>
#date 2016.09.05
#发生redis警告级别事件时通知管理员
#传递两个参数，一个是事件名，一个是事件描述

EMAIL=xiaolei@16fan.com
date=`date +%Y/%m/%d-%H:%M:%S`
warning=/usr/local/redis/log/warning.log
echo -e "WARNING EVENT EXCEPTION at ${date}.\nEVENT: ${1}\nDESC: ${2}" > $warning
cat $warning | mail  -s "Redis Warning Notice!" $EMAIL