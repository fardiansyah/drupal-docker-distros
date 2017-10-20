#!/bin/sh
# Custom script to install software on the server. Run with 'sudo'.

DOMAIN="distros.bid"
SUBDOMAIN="drupal.distros.bid"
NGINXPORT="8055"
PORTAINERPORT="9988"

user="$(id -un 2>/dev/null || true)"

  sh_c='sh -c'
  if [ "$user" != 'root' ]; then
    if command_exists sudo; then
      sh_c='sudo -E sh -c'
    elif command_exists su; then
      sh_c='su -c'
    else
      cat >&2 <<-'EOF'
      Error: this installer needs the ability to run commands as root.
      We are unable to find either "sudo" or "su" available to make this happen.
EOF
      exit 1
    fi
  fi

# Generic software
apt-get -qqy update
apt-get install -y --force-yes git wget vim zip apache2 php7.0 php7.0-mbstring

# Composer
wget -q https://github.com/composer/composer/releases/download/1.4.2/composer.phar
chmod +x composer.phar && \
mv composer.phar /usr/local/bin/composer

# Docker. Notice that we do not install latest Docker to support Rancher
# curl https://get.docker.com | sh
curl https://releases.rancher.com/install-docker/17.06.sh | sh

# Start nginx-proxy on port $NGINXPORT
docker run -d -p ${NGINXPORT}:80 --name proxy \
 -v /var/run/docker.sock:/tmp/docker.sock:ro jwilder/nginx-proxy

# Add www-data to group docker
#usermod -aG docker www-data

# Start Portainer dashboard
docker volume create portainer_data
docker run -d -p ${PORTAINERPORT}:9000 -v /var/run/docker.sock:/var/run/docker.sock \
 -v portainer_data:/data portainer/portainer

# Clone web files
rm -rf /var/www/html
git clone https://github.com/theodorosploumis/drupal-docker-distros.git /var/distros/

# Install php packages
cd /var/www/distros/html && \
COMPOSER=composer.json composer install --quiet --no-ansi --no-dev --no-interaction --no-progress

# Create virtualhost sudbomain
mkdir -p /var/www/${SUBDOMAIN}
cp yes | cp -f /var/distros/scripts/000-default.conf /etc/apache2/sites-available/000-default.conf
cp yes | cp -f /var/distros/scripts/"${SUBDOMAIN}".conf /etc/apache2/sites-available/"${SUBDOMAIN}".conf
service apache2 reload

# Install DogitalOcean monitoring
curl -sSL https://agent.digitalocean.com/install.sh | sh

# Pull all docker images
bash /var/www/distros/scripts/pull-images.sh




