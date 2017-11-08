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

# Update Yves and Zed Nginx configuration files with the correct domain names
j2 /etc/nginx/conf.d/vhost-yves.conf.j2 > /etc/nginx/conf.d/vhost-yves.conf
j2 /etc/nginx/conf.d/vhost-zed.conf.j2 > /etc/nginx/conf.d/vhost-zed.conf

# Put Zed host IP to /etc/hosts file:
echo "127.0.0.1	$ZED_HOST" >> /etc/hosts

# Get Spryker demoshop from the official github repo
wget https://github.com/spryker/demoshop/archive/master.tar.gz
tar --strip-components=1  -xzf master.tar.gz -C ./
rm master.tar.gz

# Install all modules for Spryker
composer install

# Enable PGPASSWORD for non-interactive working with PostgreSQL
export PGPASSWORD=$POSTGRES_PASSWORD
# Kill all others connections/sessions to the PostgreSQL for avoiding an error in the next command
psql --username=$POSTGRES_USER --host=$POSTGRES_HOST $POSTGRES_DATABASE -c 'SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid();'
# Drop the current PostgreSQL db and create the empty one
dropdb --username=$POSTGRES_USER --host=$POSTGRES_HOST $POSTGRES_DATABASE
createdb --username=$POSTGRES_USER --host=$POSTGRES_HOST $POSTGRES_DATABASE

# Clean all Redis data
redis-cli -h $REDIS_HOST flushall

# Delete the de_search index of the Elasticsearch
curl -XDELETE $ELASTICSEARCH_HOST:$ELASTICSEARCH_PORT/de_search

# Prepare the config_local.php config from the template
j2 config_local.php.j2 > config/Shared/config_local.php

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

# Install front-end
npm install
for module in braintree; do
  (cd /data/vendor/spryker/${module}/assets/Yves; npm install)
done
for module in gui discount product-relation; do
  (cd /data/vendor/spryker/${module}/assets/Zed; npm install)
done
npm run yves
npm run zed

# Save environment variable to the env.txt for remote Jenkins jobs
##env > /data/deploy/docker/env.txt

cp /etc/nginx/nginx.conf.bk /etc/nginx/nginx.conf
killall -9 nginx

chown -R www-data:www-data /data

# Call command...
exec $*
