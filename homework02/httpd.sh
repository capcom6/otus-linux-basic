#!/bin/bash

read -r -d '' NGINX_CONFIG <<-TEXT
# For more information on configuration, see:
#   * Official English Documentation: http://nginx.org/en/docs/
#   * Official Russian Documentation: http://nginx.org/ru/docs/

user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

# Load dynamic modules. See /usr/share/doc/nginx/README.dynamic.
include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 2048;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    # Load modular configuration files from the /etc/nginx/conf.d directory.
    # See http://nginx.org/en/docs/ngx_core_module.html#include
    # for more information.
    include /etc/nginx/conf.d/*.conf;

    server {
        listen       {{PORT}} default_server;
        listen       [::]:{{PORT}} default_server;
        server_name  _;
        root         /usr/share/nginx/html;

        # Load configuration files for the default server block.
        include /etc/nginx/default.d/*.conf;

        location / {
            proxy_pass http://httpd;
        }

        error_page 404 /404.html;
        location = /404.html {
        }

        error_page 500 502 503 504 /50x.html;
        location = /50x.html {
        }
    }

}

TEXT

function setup_nginx {
    PORT=$1

    for i in "$@"
    do
    case $i in
        -b=*|--backend=*)
        BACKENDS="${i#*=}"
        ;;
        *)
            # unknown option
        ;;
    esac
    done

    if [[ -z "$BACKENDS" ]]; then
        echo "!!! Pass minimum one backend address to -b option"
        exit 1
    fi

    # generate nginx config
    NGINX_UPSTREAM="/etc/nginx/conf.d/upstream.conf"
    echo "upstream httpd {" > $NGINX_UPSTREAM
    IFS=',' read -ra ADDR <<< "$BACKENDS"
    for i in "${ADDR[@]}"; do
        echo "    server $i;" >> $NGINX_UPSTREAM
    done
    echo "}" >> $NGINX_UPSTREAM

    yum install -y epel-release && yum install -y nginx\
    && cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak\
    && sed "s/{{PORT}}/$PORT/g" <<< "$NGINX_CONFIG" > /etc/nginx/nginx.conf\
    && systemctl enable nginx && systemctl start nginx
}

function setup_apache {
    PORT=$1

    yum install -y httpd \
    && sed -i.bak "s/^Listen.*$/Listen ${PORT}/" /etc/httpd/conf/httpd.conf \
    && systemctl enable httpd && systemctl start httpd
}

function show_help {
    NAME_LENGTH=$((35 - `echo "$0" | wc -m`))
    # echo "'$NAME_LENGTH'"
    SPACER=`printf ' %.0s' $(seq 1 $NAME_LENGTH)`

    echo "######################################################################"
    echo "# This script allows you to setup nginx + apache on CentOS 7         #"
    echo "# You must be root to run this script                                #"
    echo "# Usage $0 (nginx | apache) [options]$SPACER#"
    echo "#                                                                    #"
    echo "# nginx|apache installation target                                   #"
    echo "#                                                                    #"
    echo "# Common options:                                                    #"
    echo "#   -p=port - listen port for target                                 #"
    echo "#                                                                    #"
    echo "# Nginx options:                                                     #"
    echo "#   -b=backend - comma-separated list of backend addresses with port #"
    echo "######################################################################"
}

if [ $# -lt 1 ]; then
    show_help
    exit 0
fi

if [ `id -u` -ne 0 ]; then
    echo "!!! You must be root to run this script"
    exit 1
fi

for i in "$@"
do
case $i in
    -p=*|--port=*)
    PORT="${i#*=}"
    ;;
    *)
          # unknown option
    ;;
esac
done

case "$1" in
    "apache")
        setup_apache $PORT $@
    ;;
    "nginx")
        setup_nginx $PORT $@
    ;;
    *)
        show_help
    ;;
esac
