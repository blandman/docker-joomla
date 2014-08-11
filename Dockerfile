######## data-store
FROM ubuntu:14.04
MAINTAINER Frank Lemanschik <frank@dspeed.eu>
# OLD MAINTAINER Martin Gondermann magicmonty@pagansoft.de

RUN DEBIAN_FRONTEND="noninteractive" && \
	echo "deb http://archive.ubuntu.com/ubuntu trusty main universe" >> /etc/apt/sources.list && \
	apt-get update && \
	apt-get -y upgrade && \
	apt-get -y install curl unzip && \
	apt-get clean && \
	rm -rf /var/lib/apt/lists/*

# Create data directories
RUN mkdir -p /data/mysql /data/www

RUN curl -G -o /data/joomla.zip http://joomlacode.org/gf/download/frsrelease/19239/158104/Joomla_3.2.3-Stable-Full_Package.zip && \
	unzip /data/joomla.zip -d /data/www && \
	rm /data/joomla.zip

# Create /data volume
VOLUME ["/data"]

CMD /bin/sh

# MariaDB (https://mariadb.org/)
FROM ubuntu:14.04
MAINTAINER Martin Gondermann magicmonty@pagansoft.de

# Set noninteractive mode for apt-get
ENV DEBIAN_FRONTEND noninteractive

RUN echo " deb http://archive.ubuntu.com/ubuntu trusty main universe" > /etc/apt/sources.list && \
	apt-get update && \
	apt-get upgrade -y && \
	apt-get -y -q install wget logrotate

# Ensure UTF-8
RUN apt-get update
RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8

# Install MariaDB from repository.
RUN	apt-get update -y  && \
	apt-get install -y mariadb-server

# Decouple our data from our container.
VOLUME ["/data"]

# Configure the database to use our data dir.
RUN sed -i -e 's/^datadir\s*=.*/datadir = \/data\/mysql/' /etc/mysql/my.cnf

# Configure MariaDB to listen on any address.
RUN sed -i -e 's/^bind-address/#bind-address/' /etc/mysql/my.cnf
EXPOSE 3306
#ADD site-db/start.sh /start.sh
ENV START_SH << SSEOF 
#!/bin/bash
# Starts up MariaDB within the container.
# Stop on error
	set -e
	DATADIR="/data/mysql"
	/etc/init.d/mysql stop
# test if DATADIR has content
	if [ ! "$(ls -A $DATADIR)" ]; then
  		echo "Initializing MariaDB at $DATADIR"
  		# Copy the data that we generated within the container to the empty DATADIR.
  		cp -R /var/lib/mysql/* $DATADIR
	fi
# Ensure mysql owns the DATADIR
chown -R mysql $DATADIR
chown root $DATADIR/debian*.flag
# The password for 'debian-sys-maint'@'localhost' is auto generated.
# The database inside of DATADIR may not have been generated with this password.
# So, we need to set this for our database to be portable.
echo "Setting password for the 'debian-sys-maint'@'localhost' user"
/etc/init.d/mysql start
sleep 1
DB_MAINT_PASS=$(cat /etc/mysql/debian.cnf |grep -m 1 "password\s*=\s*"| sed 's/^password\s*=\s*//')
mysql -u root -e \
  "GRANT ALL PRIVILEGES ON *.* TO 'debian-sys-maint'@'localhost' IDENTIFIED BY '$DB_MAINT_PASS';"
# Create the superuser named 'docker'.
mysql -u root -e \
  "DELETE FROM mysql.user WHERE user='docker'; CREATE USER 'docker'@'localhost' IDENTIFIED BY 'docker'; GRANT ALL PRIVILEGES ON *.* TO 'docker'@'localhost' WITH GRANT OPTION; CREATE USER 'docker'@'%' IDENTIFIED BY 'docker'; GRANT ALL PRIVILEGES ON *.* TO 'docker'@'%' WITH GRANT OPTION;" && \
  /etc/init.d/mysql stop
SSEOF
RUN cat $STARTSH > start.sh

RUN chmod +x /start.sh
ENTRYPOINT ["/start.sh"]

FROM ubuntu:precise
MAINTAINER magicmonty@pagansoft.de

# Install all that’s needed
ENV DEBIAN_FRONTEND noninteractive
RUN echo "deb http://archive.ubuntu.com/ubuntu precise main universe" > /etc/apt/sources.list && \
	apt-get update && \
	apt-get -y upgrade && \
	apt-get -y install mysql-client apache2 libapache2-mod-php5 pwgen python-setuptools vim-tiny php5-mysql openssh-server sudo php5-ldap unzip && \
	apt-get clean && \
	rm -rf /var/lib/apt/lists/*
RUN easy_install supervisor

# Create! --Add-- all config and start files
RUN cat << SEOF > /start.sh
#!/bin/bash
# Alternate method change user id of www-data to match file owner!
chown -R www-data:www-data /data/www
supervisord -n
SEOF

RUN cat << EOF > /etc/supervisord.conf
# /etc/supervisord.conf
[unix_http_server]
file=/tmp/supervisor.sock                       ; path to your socket file

[supervisord]
logfile=/var/log/supervisord/supervisord.log    ; supervisord log file
logfile_maxbytes=50MB                           ; maximum size of logfile before rotation
logfile_backups=10                              ; number of backed up logfiles
loglevel=error                                  ; info, debug, warn, trace
pidfile=/var/run/supervisord.pid                ; pidfile location
nodaemon=false                                  ; run supervisord as a daemon
minfds=1024                                     ; number of startup file descriptors
minprocs=200                                    ; number of process descriptors
user=root                                       ; default user
childlogdir=/var/log/supervisord/               ; where child log files will live

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///tmp/supervisor.sock         ; use a unix:// URL  for a unix socket

[program:httpd]
command=/etc/apache2/foreground.sh
stopsignal=6

;sshd
[program:sshd]
command=/usr/sbin/sshd -D
stdout_logfile=/var/log/supervisord/%(program_name)s.log
stderr_logfile=/var/log/supervisord/%(program_name)s.log
autorestart=true
EOF

RUN cat << EOF > /etc/apache2/foreground.sh
#!/bin/bash

read pid cmd state ppid pgrp session tty_nr tpgid rest < /proc/self/stat
trap "kill -TERM -$pgrp; exit" EXIT TERM KILL SIGKILL SIGTERM SIGQUIT

source /etc/apache2/envvars
apache2 -D FOREGROUND
EOF

RUN mkdir -p /var/log/supervisord /var/run/sshd
RUN chmod 755 /start.sh && chmod 755 /etc/apache2/foreground.sh

# Set Apache user and log
ENV APACHE_RUN_USER www-data
ENV APACHE_RUN_GROUP www-data
ENV APACHE_LOG_DIR /var/log/apache2
ENV DOCKER_RUN "docker run -d -name my-web-machine -p 80:80 -p 9000:22 -link my-site-db:mysql -volumes-from my-data-store web-machine"
VOLUME ["/data"]

# Add site to apache
ADD ./joomla /etc/apache2/sites-available/
RUN a2ensite joomla
RUN a2dissite 000-default

# Set root password to access through ssh
RUN echo "root:desdemona" | chpasswd

# Expose web and ssh
EXPOSE 80
EXPOSE 22

CMD ["/bin/bash", "/start.sh"]
