#redis-deploy
这是一个生产环境的Redis部署脚本。

#安装
```
git clone https://github.com/xiaolei16fan/redis-deploy.git
cd redis-deploy
chmod +x ./*
```

#部署步骤
每个文件名表示相应的服务器。比如`server_d`表示服务器D，以此类推。

1. 在每个服务器上都`clone`一下这个仓库
2. 在每个服务器上执行对应脚本