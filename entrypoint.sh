#!/bin/bash -x

cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bk
cp /etc/nginx/nginx_waiting.conf /etc/nginx/nginx.conf
/usr/sbin/nginx -g 'daemon on;' &

# Waiting for PostgreSQL database starting
until PGPASSWORD=$POSTGRES_PASSWORD psql -h $POSTGRES_HOST -p "$POSTGRES_PORT" -U "$POSTGRES_USER" $POSTGRES_DATABASE -c '\l'; do
  echo "Waiting for PostgreSQL..."
  sleep 3
done
echo "PostgreSQL is available now. Good."

# Waiting for the Elasticsearch starting
until curl -s "$ELASTICSEARCH_HOST:$ELASTICSEARCH_PORT" > /dev/null; do
  echo "Waiting for Elasticsearch..."
  sleep 3
done
echo "Elasticsearch is available now. Good."

# Become more verbose
set -xe

# Generate configuration files
j2 deploy/docker/config_local.php.j2 > config/Shared/config_local.php

# Update Yves and Zed Nginx configuration files with the correct domain names
j2 /etc/nginx/conf.d/vhost-yves.conf.j2 > /etc/nginx/conf.d/vhost-yves.conf
j2 /etc/nginx/conf.d/vhost-zed.conf.j2 > /etc/nginx/conf.d/vhost-zed.conf

# Put Zed host IP to /etc/hosts file:
echo "127.0.0.1	$ZED_HOST" >> /etc/hosts

# Setup code (this should be moved to build container/build action on CI)
#npm install -g antelope
#npm install
#
#for bundle in Braintree; do
#  (cd vendor/spryker/spryker/Bundles/${bundle}/assets/Yves; npm install)
#done
#
#for bundle in  Gui ProductRelation Discount NavigationGui; do
#  (cd vendor/spryker/spryker/Bundles/${bundle}/assets/Zed; npm install)
#done
#npm run yves
#npm run zed

# Full app install
vendor/bin/console setup:install

# Import demo data
vendor/bin/console data:import

# Update product label relation
##vendor/bin/console product-label:relations:update

# Run collectors
vendor/bin/console collector:search:export
vendor/bin/console collector:storage:export

# Setup Jenkins cronjobs
##vendor/bin/console setup:jenkins:enable
##vendor/bin/console setup:jenkins:generate

# Save environment variable to the env.txt for remote Jenkins jobs
env > /data/deploy/docker/env.txt

cp /etc/nginx/nginx.conf.bk /etc/nginx/nginx.conf
killall -9 nginx

chown -R www-data:www-data /data

# Call command...
exec $*
