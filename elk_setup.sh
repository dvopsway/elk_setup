#!/bin/sh
############################################################################################################################
#   Name                :  setup_elk.sh                                                                                    #
#   Purpose             :  Setup elasticsearch, kibana , logstash and nginx and congure them                               #
#   ------ -------------------  ------------------------------  ---------------------------------------                    #
#   Ver        Date                    Author                       Description                                            #
#   ------ -------------------  ------------------------------  ---------------------------------------                    #
#   1.0     6-Jan-16                  Padmakar Ojha              Initial Development of script						                 #
############################################################################################################################

# Intialize Variables
SCRIPT_DIRECTORY=$PWD
INSTALL_LOG="$SCRIPT_DIRECTORY/install.log"
ELASTICSEARCH_REPO="/etc/yum.repos.d/elasticsearch.repo"
LOGSTASH_REPO="/etc/yum.repos.d/elasticsearch.repo"
INPUT_FILE="/etc/logstash/conf.d/01-lumberjack-input.conf"
OUTPUT_FILE="/etc/logstash/conf.d/30-lumberjack-output.conf"
ip=`facter ipaddress_eth0`

# Installing java dependency
{
  echo "installing dependencies"
  yum -y install java-1.7.0-openjdk >> $INSTALL_LOG
} || {
  echo "failed dependency installation, check install.log for more details"
  exit
}

# elasticsearch setup
printf "setup elasticsearch:\n"
{
  sudo rpm --import http://packages.elasticsearch.org/GPG-KEY-elasticsearch >> $INSTALL_LOG
  printf "[elasticsearch-1.1]\nname=Elasticsearch repository for 1.1.x packages\nbaseurl=http://packages.elasticsearch.org/elasticsearch/1.1/centos\ngpgcheck=1\ngpgkey=http://packages.elasticsearch.org/GPG-KEY-elasticsearch\nenabled=1\n" >> $ELASTICSEARCH_REPO
  printf "installing elastic\nplease wait..."
  yum -y install elasticsearch-1.1.1 >> $INSTALL_LOG

  echo "configuring elastic"
  echo "script.disable_dynamic: true" >> /etc/elasticsearch/elasticsearch.yml
  sed -i -r  '/network.host/c network.host: localhost'  /etc/elasticsearch/elasticsearch.yml
  sed -i -r  '/discovery.zen.ping.multicast.enabled/c discovery.zen.ping.multicast.enabled: false'  /etc/elasticsearch/elasticsearch.yml

  service elasticsearch restart >> $INSTALL_LOG
  /sbin/chkconfig --add elasticsearch >> $INSTALL_LOG
  echo "elastic setup complete"
} || {
  echo "failed elasticsearch installation, check install.log for more details"
  exit
}

# setup kibana
{
  echo "setup kibana"
  cd ~
  echo "downloading kibana"
  curl -O https://download.elasticsearch.org/kibana/kibana/kibana-3.0.1.tar.gz >> $INSTALL_LOG
  tar xvf kibana-3.0.1.tar.gz >> $INSTALL_LOG
  echo "configuring kibana"
  sed -i -r  '/window.location.hostname/c elasticsearch: "http://"+window.location.hostname+":80",' ~/kibana-3.0.1/config.js
  mkdir -p /usr/share/nginx/kibana3
  cp -R ~/kibana-3.0.1/* /usr/share/nginx/kibana3/ >> $INSTALL_LOG
} || {
  echo "failed kibana installation, check install.log for more details"
  exit
}

# setup nginx
{
  echo "setup nginx"
  rpm -Uvh http://download.fedoraproject.org/pub/epel/6/i386/epel-release-6-8.noarch.rpm >> $INSTALL_LOG
  yum -y install nginx >> $INSTALL_LOG
  cd ~
  curl -OL https://gist.githubusercontent.com/thisismitch/2205786838a6a5d61f55/raw/f91e06198a7c455925f6e3099e3ea7c186d0b263/nginx.conf >> $INSTALL_LOG
  sed -i -r  '/root/c root  /usr/share/nginx/kibana3;' ~/nginx.conf
  sed -i.bak '/server_name/d' ~/nginx.conf
  cp ~/nginx.conf /etc/nginx/conf.d/default.conf
  yum -y install httpd-tools-2.2.15 >> $INSTALL_LOG
  echo "admin:8gs2h8cKq1T0Y" >> /etc/nginx/conf.d/kibana.myhost.org.htpasswd
  service nginx restart >> $INSTALL_LOG
  chkconfig --levels 235 nginx on >> $INSTALL_LOG
} || {
  echo "failed nginx installation, check install.log for more details"
  exit
}

# setup logstash
{
  echo "setup logstash"
  printf "[logstash-1.4]\nname=logstash repository for 1.4.x packages\nbaseurl=http://packages.elasticsearch.org/logstash/1.4/centos\ngpgcheck=1\ngpgkey=http://packages.elasticsearch.org/GPG-KEY-elasticsearch\nenabled=1\n" >> $LOGSTASH_REPO
  yum -y install logstash-1.4.2 facter >> $INSTALL_LOG
  sed -i "/\[ v3_ca/a subjectAltName = IP: $ip" /etc/pki/tls/openssl.cnf
  cd /etc/pki/tls
  openssl req -config /etc/pki/tls/openssl.cnf -x509 -days 3650 -batch -nodes -newkey rsa:2048 -keyout private/logstash-forwarder.key -out certs/logstash-forwarder.crt >> $INSTALL_LOG
  cp $SCRIPT_DIRECTORY/01-lumberjack-input.conf /etc/logstash/conf.d/01-lumberjack-input.conf
  printf "input {\nlumberjack {\nport => 5000\ntype => \"logs\"\nssl_certificate => \"/etc/pki/tls/certs/logstash-forwarder.crt\"\nssl_key => \"/etc/pki/tls/private/logstash-forwarder.key\"\n}\n}\n" >> $INPUT_FILE
  cp $SCRIPT_DIRECTORY/30-lumberjack-output.conf /etc/logstash/conf.d/30-lumberjack-output.conf
  printf "output {\nelasticsearch { host => localhost }\nstdout { codec => rubydebug }\n}" >> $OUTPUT_FILE
  service logstash restart >> $INSTALL_LOG
} || {
  echo "failed logstash installation, check install.log for more details"
  exit
}

echo "Your ELK Setup is complete, access it from http://$ip:80"
