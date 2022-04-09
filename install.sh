#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}未检测到系统版本，请联系作者！${plain}\n" && exit 1
fi

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    exit 2
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi

if [[ ${os_version} -le 6 ]]; then
	echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
fi


install_ready() {
	read -p "请输入root用户的密码:" root_passwd

	echo "正在关闭防火墙！"
    systemctl disable firewalld
    systemctl stop firewalld
	echo "正在修改hostname为node1"
	hostname node1
	sed -i '$a\node1' /etc/hostname
	sed -i '1d' /etc/hostname
	echo "正在修改hosts文件"
	hosts_tmp=`cat /etc/hosts | grep node1`
	if [[ ! $hosts_tmp =~ 'node1' ]];then
	  ip_tmp=`ip addr`
	  if [[ $ip_tmp =~ 'eth0' ]];then
	    ip=$(ip addr |grep inet |grep -v inet6 |grep eth0|awk '{print $2}' |awk -F "/" '{print $1}');
	  elif [[ $ip_tmp =~ 'ens33' ]];then
	    ip=$(ip addr |grep inet |grep -v inet6 |grep ens33|awk '{print $2}' |awk -F "/" '{print $1}');
	  elif [[ $ip_tmp =~ 'ens32' ]];then
	    ip=$(ip addr |grep inet |grep -v inet6 |grep ens32|awk '{print $2}' |awk -F "/" '{print $1}');
	  fi
	echo $ip;
	sed -i '$a\'"$ip"' node1' /etc/hosts;
	else
	echo "已存在"
	echo $hosts_tmp;
	fi
	
	echo "正在创建工作目录"
	mkdir -p /export/software
	mkdir -p /export/server
	
	echo "配置本机免密登录（hadoop必须）"
	
	sshd_tmp=`cat /etc/ssh/sshd_config | grep '#PermitRootLogin yes'`
	if [[ ! $sshd_tmp = '#PermitRootLogin yes' ]];then
	echo "PermitRootLogin is yes"
	else
	sed -i 's|#PermitRootLogin yes|PermitRootLogin yes|g' /etc/ssh/sshd_config
	echo "修改成功"
	fi
	
	yum -y install expect
	if [ ! -f ~/.ssh/id_rsa ];then
	ssh-keygen -t rsa -P "" -f ~/.ssh/id_rsa
	else
	 echo "id_rsa has created ..."
	fi

	expect <<EOF
	spawn ssh-copy-id node1
	expect {
	"yes/no" { send "yes\n";exp_continue }
	"password" { send "$root_passwd\n" }
	}
	expect "password" { send "$root_passwd\n" }
EOF
	expect <<EOF
	spawn ssh node1
	expect {
	"yes/no" { send "yes\n"; }
	}
EOF
	echo "准备工作已完成"
	
}

install_jdk() {
	echo "开始安装jdk"
	echo "开始下载jdk"
	
	if [[ ! -f /export/software/jdk-8u241-linux-x64.tar.gz ]]; then
	wget --no-check-certificate -P /export/software http://ra2ljkp3p.hn-bkt.clouddn.com/jdk-8u241-linux-x64.tar.gz
	echo "下载jdk完成"
	else
	echo "jdk安装包已存在"
	fi
	
	
	echo "开始解压jdk"
	tar zxf /export/software/jdk-8u241-linux-x64.tar.gz -C /export/server
	echo "解压jdk完成"
	echo "开始添加jdk环境变量"
	sed -i '$a\JAVA_HOME=/export/server/jdk1.8.0_241\n\CLASSPATH=.:$JAVA_HOME/lib\n\PATH=$JAVA_HOME/bin:$PATH\n\export JAVA_HOME CLASSPATH PATH' /etc/profile
	source /etc/profile;
	javacheck=`java -version 2>&1 | sed '1!d' | sed -e 's/"//g' | awk '{print $3}'`
	if [ $javacheck = '1.8.0_241' ]; then
	echo -e "jdk${javacheck}已安装";
	java_install='true';
	else
	echo -e "jdk安装失败";
	java_install='false';
	fi
}

install_zookeeper() {
	echo "开始安装zookeeper"
	echo "开始下载zookeeper"
	
	if [[ ! -f /export/software/apache-zookeeper-3.5.9-bin.tar.gz ]]; then
	wget --no-check-certificate -P /export/software https://mirrors.tuna.tsinghua.edu.cn/apache/zookeeper/zookeeper-3.5.9/apache-zookeeper-3.5.9-bin.tar.gz
	echo "zookeeper下载完成"
	else
	echo "zookeeper安装包已存在"
	fi
	
	tar zxf /export/software/apache-zookeeper-3.5.9-bin.tar.gz -C /export/server/
	mv /export/server/zookeeper-3.5.9-bin /export/server/zookeeper
	mkdir -p /export/data/zkdata
	cp /export/server/zookeeper/conf/zoo_sample.cfg /export/server/zookeeper/conf/zoo.cfg
	sed -i 's|/tmp/zookeeper|/export/data/zkdata|g' /export/server/zookeeper/conf/zoo.cfg
	/export/server/zookeeper/bin/zkServer.sh start
	zoocheck=`/export/server/zookeeper/bin/zkServer.sh status`
	if [[ $zoocheck = 'Mode: standalone' ]]; then
	echo -e "zookeeper 已安装";
	echo -e "zookeeper 已运行在${zoocheck}模式";
	zoo_install=true;
	else
	echo -e "zookeeper安装失败";
	zoo_install=false;
	fi
	/export/server/zookeeper/bin/zkServer.sh stop
}

install_hadoop() {
	echo "开始安装hadoop"
	echo "开始下载hadoop"
	
	if [[ ! -f /export/software/hadoop-3.3.0.tar.gz ]]; then
	wget --no-check-certificate -P /export/software https://archive.apache.org/dist/hadoop/common/hadoop-3.3.0/hadoop-3.3.0.tar.gz
	echo "hadoop下载完成"
	else
	echo "hadoop安装包已存在"
	fi
	
	
	echo "开始解压hadoop"
	tar -zxf /export/software/hadoop-3.3.0.tar.gz -C /export/server/
	echo "hadoop解压完成"
	echo "开始修改配置文件"
	sed -i '$a\export JAVA_HOME=/export/server/jdk1.8.0_241\n\export HDFS_NAMENODE_USER=root\n\export HDFS_DATANODE_USER=root\n\export HDFS_SECONDARYNAMENODE_USER=root\n\export YARN_RESOURCEMANAGER_USER=root\n\export YARN_NODEMANAGER_USER=root' /export/server/hadoop-3.3.0/etc/hadoop/hadoop-env.sh
	mv /export/server/hadoop-3.3.0/etc/hadoop/core-site.xml /export/server/hadoop-3.3.0/etc/hadoop/core-site.xml.bak
	mv /export/server/hadoop-3.3.0/etc/hadoop/hdfs-site.xml /export/server/hadoop-3.3.0/etc/hadoop/hdfs-site.xml.bak
	mv /export/server/hadoop-3.3.0/etc/hadoop/mapred-site.xml /export/server/hadoop-3.3.0/etc/hadoop/mapred-site.xml.bak
	mv /export/server/hadoop-3.3.0/etc/hadoop/yarn-site.xml /export/server/hadoop-3.3.0/etc/hadoop/yarn-site.xml.bak
	mv /export/server/hadoop-3.3.0/etc/hadoop/workers /export/server/hadoop-3.3.0/etc/hadoop/workers.bak
	wget -P /export/server/hadoop-3.3.0/etc/hadoop/ http://suhang.work/hadoop_etc/core-site.xml
	wget -P /export/server/hadoop-3.3.0/etc/hadoop/ http://suhang.work/hadoop_etc/hdfs-site.xml
	wget -P /export/server/hadoop-3.3.0/etc/hadoop/ http://suhang.work/hadoop_etc/mapred-site.xml
	wget -P /export/server/hadoop-3.3.0/etc/hadoop/ http://suhang.work/hadoop_etc/yarn-site.xml
	wget -P /export/server/hadoop-3.3.0/etc/hadoop/ http://suhang.work/hadoop_etc/workers
	echo "hadoop修改配置文件完成"
	echo "开始添加环境变量"
	sed -i '$a\export HADOOP_HOME=/export/server/hadoop-3.3.0\n\export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin' /etc/profile
	source /etc/profile
	hdfs namenode -format
	echo "格式化namenode完成"
	if [[ -e /export/server/hadoop-3.3.0 ]]; then
	echo "hadoop已安装"
	hadoop_install=true;
	else
	echo -e "hadoop安装失败"
	hadoop_install=false;
	fi
	/export/server/hadoop-3.3.0/sbin/start-all.sh
}

install_mysql() {
	mysql_passwd='hadoop666'
	echo "开始安装mysql"
	mariadb=`rpm -qa|grep mariadb`
	rpm -e $mariadb --nodeps
	mkdir /export/software/mysql
	echo "开始下载mysql"
	
	if [[ ! -f /export/software/mysql/mysql-5.7.29-1.el7.x86_64.rpm-bundle.tar ]]; then
	wget --no-check-certificate -P /export/software/mysql https://downloads.mysql.com/archives/get/p/23/file/mysql-5.7.29-1.el7.x86_64.rpm-bundle.tar
	echo "mysql下载完成"
	else
	echo "mysql安装包已存在"
	fi
	
	cd /export/software/mysql
	echo "开始解压mysql"
	tar -xvf /export/software/mysql/mysql-5.7.29-1.el7.x86_64.rpm-bundle.tar -C /export/software/mysql
	echo "解压完成"
	yum -y install libaio
	yum -y install numactl
	rpm -ivh mysql-community-common-5.7.29-1.el7.x86_64.rpm mysql-community-libs-5.7.29-1.el7.x86_64.rpm mysql-community-client-5.7.29-1.el7.x86_64.rpm mysql-community-server-5.7.29-1.el7.x86_64.rpm 
	echo "初始化mysql"
	mysqld --initialize
	chown mysql:mysql /var/lib/mysql -R
	systemctl start mysqld.service
	tmp_passwd=`grep 'temporary password' /var/log/mysqld.log | awk '{print $11}'`
	mysql --connect-expired-password -uroot -p$tmp_passwd << EOF
	alter user user() identified by "hadoop666";
	use mysql;
	GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY 'hadoop666' WITH GRANT OPTION;
	FLUSH PRIVILEGES;
	exit
EOF
	echo "mysql开机启动"
	systemctl enable  mysqld
	mysql_tmp=`systemctl status mysqld.service | grep active`
	if [[ $mysql_tmp ]]; then
	echo "mysql已安装"
	mysql_install=true;
	else
	echo -e "mysql安装失败"
	mysql_install=false;
	fi
	cd
}

install_hive() {
	echo "开始安装hive"
	echo "开始下载hive"
	wget --no-check-certificate -P /export/software/ https://mirrors.tuna.tsinghua.edu.cn/apache/hive/hive-3.1.2/apache-hive-3.1.2-bin.tar.gz
	echo "下载完成"
	echo "开始解压hive"
	tar zxf /export/software/apache-hive-3.1.2-bin.tar.gz -C /export/server/
	mv /export/server/apache-hive-3.1.2-bin /export/server/hive-3.1.2
	rm -rf /export/server/hive-3.1.2/lib/guava-19.0.jar
	cp /export/server/hadoop-3.3.0/share/hadoop/common/lib/guava-27.0-jre.jar /export/server/hive-3.1.2/lib
	ll lib | grep guava
	wget -P /export/server/hive-3.1.2/conf http://suhang.work/hadoop_etc/hive-env.sh
	wget -P /export/server/hive-3.1.2/conf http://suhang.work/hadoop_etc/hive-site.xml
	wget -P /export/server/hive-3.1.2/lib http://suhang.work/hadoop_etc/mysql-connector-java-5.1.32.jar
	echo "开始初始化hive"
	/export/server/hive-3.1.2/bin/schematool -initSchema -dbType mysql -verbos
	/export/server/hadoop-3.3.0/bin/hadoop fs -mkdir /tmp
	/export/server/hadoop-3.3.0/bin/hadoop fs -mkdir -p /user/hive/warehouse
	/export/server/hadoop-3.3.0/bin/hadoop fs -chmod g+w /tmp
	/export/server/hadoop-3.3.0/bin/hadoop fs -chmod g+w /user/hive/warehouse

	if [[ -d /export/server/hive-3.1.2 ]]; then
	echo "hive已安装"
	hive_install=true;
	else
	echo -e "hive安装失败"
	hive_install=false;
	fi

}


install_spark() {
  echo "开始安装spark"
	echo "开始下载spark"
	wget --no-check-certificate -P /export/software/ https://mirrors.tuna.tsinghua.edu.cn/apache/spark/spark-3.1.2/spark-3.1.2-bin-hadoop3.2.tgz
	echo "下载完成"
	echo "开始解压spark"
	tar zxf /export/software/spark-3.1.2-bin-hadoop3.2.tgz -C /export/server/
	mv /export/server/spark-3.1.2-bin-hadoop3.2 /export/server/spark
	echo "开始修改spark配置文件"
	cp /export/server/spark/conf/spark-env.sh.template /export/server/spark/conf/spark-env.sh
	cp /export/server/spark/conf/spark-defaults.conf.template /export/server/spark/conf/spark-defaults.conf
	sed -i '$a\HADOOP_CONF_DIR=/export/server/hadoop/etc/hadoop\n\YARN_CONF_DIR=/export/server/hadoop/etc/hadoop' /export/server/spark/conf/spark-env.sh
	sed -i '$a\spark.eventLog.enabled true\n\spark.eventLog.dir hdfs://node1:8020/sparklog/\n\spark.eventLog.compress true\n\spark.yarn.historyServer.address node1:18080\n\spark.yarn.jars  hdfs://node1:8020/spark/jars/*' /export/server/spark/conf/spark-defaults.conf
  wget -P /export/server/spark/conf http://suhang.work/hadoop_etc/log4j.properties
  wget -P /export/server/spark/jars http://suhang.work/hadoop_etc/mysql-connector-java-5.1.32.jar
  wget -P /export/server/spark/conf http://suhang.work/hadoop_etc/hive-site.xml
  echo "此处会卡一会儿，属于正常情况，请耐心等待"
  /export/server/hadoop-3.3.0/bin/hadoop fs -mkdir -p /spark/jars/
  /export/server/hadoop-3.3.0/bin/hadoop fs -put /export/server/spark/jars/* /spark/jars/
  /export/server/hadoop-3.3.0/bin/hadoop fs -mkdir -p /sparklog
  echo "开始下载anaconda3"
  wget --no-check-certificate -P /export/software/ https://mirrors.tuna.tsinghua.edu.cn/anaconda/archive/Anaconda3-2021.05-Linux-x86_64.sh
  echo "开始安装anaconda3"
  sh /export/software/Anaconda3-2021.05-Linux-x86_64.sh -b
  echo "开始添加环境变量"
	sed -i '$a\export ANACONDA_HOME=/root/anaconda3/bin \n\export PATH=$PATH:$ANACONDA_HOME/bin' /etc/profile
	source /etc/profile
	sed -i '1a\export PATH=~/anaconda3/bin:$PATH' /root/.bashrc
	/root/anaconda3/bin/pip install pyspark
	/root/anaconda3/bin/pip install pyspark[sql]
	if [[ -d /export/server/spark ]]; then
	echo "spark已安装"
	spark_install=true;
	else
	echo -e "spark安装失败"
	spark_install=false;
	fi
	/export/server/hadoop-3.3.0/sbin/stop-all.sh
}

install_sqoop() {
	echo "开始安装sqoop"
	echo "开始下载sqoop"

	if [[ ! -f /export/software/sqoop-1.4.7.bin__hadoop-2.6.0.tar.gz ]]; then
	wget --no-check-certificate -P /export/software http://archive.apache.org/dist/sqoop/1.4.7/sqoop-1.4.7.bin__hadoop-2.6.0.tar.gz
	echo "下载sqoop完成"
	else
	echo "sqoop安装包已存在"
	fi
	
	echo "开始解压sqoop"
	tar zxf /export/software/sqoop-1.4.7.bin__hadoop-2.6.0.tar.gz -C /export/server
	mv /export/server/sqoop-1.4.7.bin__hadoop-2.6.0 /export/server/sqoop
	echo "解压sqoop完成"
	echo "开始添加sqoop环境变量"
	sed -i '$a\export SQOOP_HOME=/export/server/sqoop' /etc/profile
	source /etc/profile;
	mv /export/server/sqoop/conf/sqoop-env-template.sh /export/server/sqoop/conf/sqoop-env.sh
	sed -i '$a\export HADOOP_COMMON_HOME= /export/server/hadoop-3.3.0\n\export HADOOP_MAPRED_HOME= /export/server/hadoop-3.3.0\n\export HIVE_HOME= /export/server/hive-3.1.2' /export/server/sqoop/conf/sqoop-env.sh
  cp /export/server/hive-3.1.2/lib/mysql-connector-java-5.1.32.jar /export/server/sqoop/lib/
  wget -P /export/server/sqoop/lib http://suhang.work/hadoop_etc/commons-lang-2.6.jar
}

install_finsh() {
	if [ java_install ]; then
	echo "jdk 安装成功";
	else
	echo "${red} jdk 安装失败";
	fi
	if [ zoo_install ]; then
	echo "zookeeper 安装成功";
	else
	echo "${red} zookeeper 安装失败";
	fi
	if [ mysql_install ]; then
	echo "mysql 安装成功";
	else
	echo "${red} mysql 安装失败";
	fi
	if [ hadoop_install ]; then
	echo "hadoop 安装成功";
	else
	echo "${red} hadoop 安装失败";
	fi
	if [ hive_install ]; then
	echo "hive 安装成功";
	else
	echo "${red} hive 安装失败";
	fi

	if [ spark_install ]; then
	echo "spark 安装成功";
	else
	echo "${red} spark 安装失败";
	fi

	echo "正在添加开机启动项"
	mkdir /export/myhadoop
	wget -P /export/myhadoop http://suhang.work/hadoop_etc/start.sh
	wget -P /export/myhadoop http://suhang.work/hadoop_etc/stop.sh
	wget -P /export/myhadoop http://suhang.work/hadoop_etc/restart.sh
	wget -P /lib/systemd/system http://suhang.work/hadoop_etc/myhadoop.service
	chmod +x /export/myhadoop/*
	systemctl daemon-reload
	systemctl enable myhadoop
	systemctl start myhadoop
	echo "开机启动项添加完成"
	clear
  echo "========================"
	if [[ java_install && zoo_install && mysql_install && hadoop_install && hive_install && spark_install ]]; then
	echo "jdk+mysql_5.7+hadoop_3.3.0+zookeeper_3.4.6+hive_3.1.2+spark_3.1.2+sqoop 已安装成功"
	echo "mysql 的默认密码为:hadoop666"

	fi
}


install_ready
install_jdk
install_mysql
install_zookeeper
install_hadoop
install_hive
install_spark
install_sqoop
install_finsh
