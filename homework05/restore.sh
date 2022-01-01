#!/bin/bash

function show_help {
    NAME_LENGTH=$((62 - `echo "$0" | wc -m`))
    # echo "'$NAME_LENGTH'"
    SPACER=`printf ' %.0s' $(seq 1 $NAME_LENGTH)`

    echo "######################################################################"
    echo "# This script allows you to setup nginx + apache on CentOS 7         #"
    echo "#                                                                    #"
    echo "# Usage $0$SPACER#"
    echo "#                                                                    #"
    echo "# Final configuration:                                               #"
    echo "#                                                                    #"
    echo "#                       -> apache at port 8081                       #"
    echo "#                     /                                              #"
    echo "# nginx at port 80 - + --> apache at port 8082                       #"
    echo "#                     \                                              #"
    echo "#                       -> apache at port 8083                       #"
    echo "#                                                                    #"
    echo "# You must be root to run this script                                #"
    echo "#                                                                    #"
    echo "######################################################################"
}

function setup_apache {
    for i in {1..3}
    do
        mkdir -p /var/www/html-808${i}
        echo "Apache 808${i}" > /var/www/html-808${i}/index.html
    done

    yum install -y -q httpd \
    && sudo cp -R -b --suffix=.orig ./conf/httpd/* /etc/httpd/ \
    && systemctl enable httpd && systemctl start httpd
}

function setup_nginx {
    yum install -y -q epel-release && yum install -y -q nginx \
    && cp -R -b --suffix=.orig ./conf/nginx/* /etc/nginx/ \
    && systemctl enable nginx && systemctl start nginx
}

if [ $# -ne 0 ]; then
    show_help
    exit 0
fi

if [ ! -d ./conf ]; then
    echo "!!! Can not find conf directory"
    exit 1
fi

if [ `id -u` -ne 0 ]; then
    echo "!!! You must be root to run this script"
    exit 1
fi

echo "+++ Setting up Apache..."
setup_apache

echo "+++ Setting up Nginx..."
setup_nginx

echo "+++ Testing..."
curl http://localhost > /dev/null

if [[ $? -ne 0 ]]; then
    echo "!!! Can not connect http://localhost"
    exit 1
fi

echo "+++ Success!"
echo "+++ Document root: /var/www/html-808*"
echo "+++ Don't forget to setup firewall"