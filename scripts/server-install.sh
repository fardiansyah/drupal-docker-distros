#!/bin/sh
# Custom script to install software on the server. Run with 'sudo'.
# Change variables according to your needs

DOMAIN="distros.bid"
SUBDOMAIN="drupal.distros.bid"
NGINXPORT="8055"

INSTALL_LETSENCYPT=0
INSTALL_RANCHER=0
INSTALL_PORTAINER=1
INSTALL_CADVISOR=0
INSTALL_ADMIRAL=0
INSTALL_ELK=0

# Monitoring system ports from 9988 - 9989
PORTAINERPORT="9988"
RANCHERPORT="9989"
CADVISORPORT="9990"
ADMIRALPORT="9991"
ELKPORT1="9200"
ELKPORT2="9201"
ELKPORT3="9202"

# Generic software
apt-get -qqy update
apt-get install -y git wget vim zip apache2 php7 php7-mbstring \
        python-certbot-apache -t stretch-backports

# Install Let's Encrypt
if [ "${INSTALL_LETSENCYPT}" -eq "1" ]; then
  certbot --apache -d ${DOMAIN} -m me@theodorosploumis.com
  certbot renew --dry-run
fi

# Composer
wget -q https://github.com/composer/composer/releases/download/1.4.2/composer.phar
chmod +x composer.phar && \
mv composer.phar /usr/local/bin/composer

# Clone git files
rm -rf /var/www/html
git clone https://github.com/theodorosploumis/drupal-docker-distros.git /var/www/distros/

# Prepare site
cp /var/www/distros/html/default.settings.php /var/www/distros/html/settings.php
chmod 444 /var/www/distros/html/settings.php

# Docker. Notice that we do not install latest Docker to support Rancher
# as also as Docker-php sdk.
# curl https://get.docker.com | sh
curl https://releases.rancher.com/install-docker/1.12.sh | sh

# Docker-compose
curl -L https://github.com/docker/compose/releases/download/1.16.1/docker-compose-`uname -s`-`uname -m` \
-o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Start nginx-proxy on port $NGINXPORT
docker run -d \
       -p ${NGINXPORT:-8055}:80 \
       --name=proxy \
       --restart=always \
       --label name=proxy \
       -v /var/run/docker.sock:/tmp/docker.sock:ro \
       jwilder/nginx-proxy

# Add www-data to group docker
usermod -aG docker www-data

# Start Portainer dashboard
if [ "${INSTALL_PORTAINER}" -eq "1" ]; then
  docker volume create --name portainer_data
  docker run -d \
         --restart=always \
         --label name=portainer \
         -p ${PORTAINERPORT:-9988}:9000 \
         -v /var/run/docker.sock:/var/run/docker.sock \
         -v portainer_data:/data \
         --name=portainer \
         portainer/portainer
fi

# Start rancher dashboard
if [ "${INSTALL_RANCHER}" -eq "1" ]; then
  docker run -d \
         -p ${RANCHERPORT}:8080 \
         --name=rancher_server \
         --restart=unless-stopped \
         rancher/server:stable
fi

# Start cAdvisor dashboard
if [ "${INSTALL_CADVISOR}" -eq "1" ]; then
   docker run \
          --restart=always \
          --volume=/:/rootfs:ro \
          --volume=/var/run:/var/run:rw \
          --volume=/sys:/sys:ro \
          --volume=/var/lib/docker/:/var/lib/docker:ro \
          --volume=/dev/disk/:/dev/disk:ro \
          --publish=${CADVISORPORT}:8080 \
          --detach=true \
          --name=cadvisor \
          google/cadvisor:latest
fi

# Start Admiral dashboard
if [ "${INSTALL_ADMIRAL}" -eq "1" ]; then
  docker run -d \
         -p ${ADMIRALPORT}:8282 \
         --restart=always \
         --name=admiral \
         --log-driver=json-file --log-opt max-size=500M --log-opt max-file=10 \
         vmware/admiral
fi

# Start ELK dashboard
# Notice that ELK stack needs at least an additional 2GB RAM!
if [ "${INSTALL_ELK}" -eq "1" ]; then
  docker run -d \
         --name=elk \
         --restart=always \
         -p ${ELKPORT2}:9200 \
         -p ${ELKPORT1}:5601 \
         -p ${ELKPORT3}:5044 \
         sebp/elk:563
fi

# Install php packages
cd /var/www/distros/html && \
COMPOSER=composer.json composer install --quiet --no-dev --no-interaction --no-progress

# Create virtualhost sudbomain
mkdir -p /var/www/${SUBDOMAIN}
yes | cp -f /var/www/distros/scripts/000-default.conf /etc/apache2/sites-available/000-default.conf
yes | cp -f /var/www/distros/scripts/"${SUBDOMAIN}".conf /etc/apache2/sites-available/"${SUBDOMAIN}".conf
a2enmod rewrite
a2ensite "${DOMAIN}"
a2ensite "${SUBDOMAIN}"
service apache2 reload

# Pull all docker images
bash /var/www/distros/scripts/pull-images.sh

# Link extra aliases
touch ~/.bashrc
echo "if [ -f /var/www/distros/scripts/.docker-aliases ]; " >> ~/.bashrc
echo "then " >> ~/.bashrc
echo ". /var/www/distros/scripts/.docker-aliases" >> ~/.bashrc
echo "fi" >> ~/.bashrc
source ~/.bashrc

# Remove unused packages
apt-get autoremove

# Add swap file
# See more here: https://www.digitalocean.com/community/tutorials/how-to-add-swap-space-on-ubuntu-16-04
fallocate -l 2G /swapfile && \
chmod 600 /swapfile && \
mkswap /swapfile && \
swapon /swapfile && \
cp /etc/fstab /etc/fstab.bak && \
echo "/swapfile none swap sw 0 0" | tee -a /etc/fstab && \
echo "vm.swappiness=10 " >> /etc/sysctl.conf && \
echo "vm.vfs_cache_pressure=50 " >> /etc/sysctl.conf && \
sysctl vm.swappiness=10 && \
sysctl vm.vfs_cache_pressure=50

# Crontab task
# */5 * * * * docker kill $(docker ps --format "{{.ID}} {{.Status}} {{.Image}}" | grep "drupal8" |  awk '{ minutes=$3; metrics=$4; max=40; if (minutes >= max && metrics == "minutes") print $3; }')

# Manually actions
# Set timezone
echo -n "Run: dpkg-reconfigure tzdata"