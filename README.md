# Hadoop-installer
Hadoop集群单节点版的一键搭建脚本 仅用于练习sql

## 说明
1. 仅支持 Centos 7 目前测试过腾讯云的 Centos7.6 和 宝塔面板应用镜像(也是Centos7.6)

2. hadoop 搭建脚本

   包含 hadoop-3.3.0           jdk-1.8.0_241 

   ​        zookeeper-3.4.6       hive-3.1.2 

   ​        spark-3.1.2               anaconda3(python3.8.8)

   ​        pyspark

3. 默认mysql密码脚本运行完毕会显示

   

## 功能
1. 非常适合怕搭环境麻烦的sql boy使用
1. 支持纯净版镜像安装hadoop集群单节点版
1. 有关hadoop的系统配置统一做初始化
1. 所有所需文件以上传个人云服务器,提供给大家无偿使用
2. 支持无人值守安装

## 使用指南
1. ssh登录进入你的服务器然后执行一下代码
```shell
bash <(curl -Ls https://cdn.jsdelivr.net/gh/suhang98/Hadoop-installer@main/install.sh)
```


2. 为了给hadoop环境做初始化需要输入你的root密码,然后稍加等待
3. And Engjoy!

   ![WechatIMG9 1](/Users/su/Desktop/WechatIMG9 1.jpeg)

<img src="/Users/su/Desktop/WechatIMG10.jpeg" alt="WechatIMG10" style="zoom:67%;" />



![WechatIMG9 1](/Users/su/Desktop/WechatIMG9 1.jpeg



## <img src="/Users/su/Desktop/WechatIMG11.jpeg" alt="WechatIMG11" style="zoom: 50%;" />

## 注意事项

如果使用云服务器搭建请注意记得在防火墙放行常用端口 ssh:22 mysql数据库:3306 hive数据仓库:10000 spark数据仓库:10001 hadoop常用端口等

由于此脚本没有经过许多环境测试,你的环境可能不适合此脚本,请纯小白勿尝试.

