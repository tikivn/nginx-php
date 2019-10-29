#!/bin/bash

PHP_VERSION="7.2"

# enable xdebug if ENV variable TK_XDEBUG_ENABLED == 1
_init_xdebug() {
  local _xdebug_enableb=0
  [[ -n "${TK_XDEBUG_ENABLED:-}" ]]   && _xdebug_enableb=$TK_XDEBUG_ENABLED

  echo ":: initializing xdebug config (_xdebug_enableb=${_xdebug_enableb})"

  if [[ $_xdebug_enableb == 1 ]] ; then
    echo -e "zend_extension=xdebug.so\nxdebug.remote_enable = on" > /etc/php/${PHP_VERSION}/mods-available/xdebug.ini
    ln -svf /etc/php/${PHP_VERSION}/mods-available/xdebug.ini /etc/php/${PHP_VERSION}/cli/conf.d/20-xdebug.ini
    ln -svf /etc/php/${PHP_VERSION}/mods-available/xdebug.ini /etc/php/${PHP_VERSION}/fpm/conf.d/20-xdebug.ini
  fi
}

# enable opcache if ENV variable APP_ENV|ENV = production or TK_OPCACHE_ENABLED == 1
_init_opcache() {
  local _opcache_enabled=0
  [[ -n "${TK_OPCACHE_ENABLED:-}" ]] && _opcache_enabled=$TK_OPCACHE_ENABLED
  [[ "${APP_ENV:-}" == "production" ]] && _opcache_enabled=1
  [[ "${ENV:-}" == "production" ]] && _opcache_enabled=1

  echo ":: initializing opcache config (_opcache_enabled=${_opcache_enabled})"

  if [[ $_opcache_enabled == 1 ]] ; then
    phpenmod opcache
  fi
}


# if ENV variable TK_IS_WORKER == 1
# -> only start worker process (dont start nginx, php-fpm)
_init_worker() {
  local _is_worker=${TK_IS_WORKER:-0}
  echo ":: initializing worker config (_is_worker=${_is_worker})"

  if [[ $_is_worker == 1 ]] ; then
    sed -i 's#autostart=.*#autostart=false#g' /etc/supervisord.conf  # dont start nginx, php-fpm
    # include worker config
    [[ -d /etc/supervisor.d ]] || mkdir -v /etc/supervisor.d
    grep -q include /etc/supervisord.conf \
    || echo -e "[include]\nfiles = /etc/supervisor.d/*.conf\n" >> /etc/supervisord.conf
  fi
}


# init supervisord eventlistener to notify to slack when a process change it's state
_init_superslacker() {
  local _is_superslacker=${TK_IS_SUPERSLACKER:-0}
  TK_SUPERVISORD_ALERT_WEBHOOK="${TK_SUPERVISORD_ALERT_WEBHOOK:-https://hooks.slack.com/services/}"
  TK_SUPERVISORD_ALERT_CHANNEL="${TK_SUPERVISORD_ALERT_CHANNEL:-system-tmp}"
  TK_SUPERVISORD_ALERT_FROM="${TK_SUPERVISORD_ALERT_FROM:-$(hostname)}"

  echo ":: initializing superslacker config (_is_superslacker=${_is_superslacker})"

  if [[ $_is_superslacker == 1 ]] ; then
    grep -q superslacker /etc/supervisord.conf \
    || cat >> /etc/supervisord.conf \
<<-EOF
[eventlistener:superslacker]
command=superslacker --webhook=${TK_SUPERVISORD_ALERT_WEBHOOK} --channel=${TK_SUPERVISORD_ALERT_CHANNEL} --hostname=${TK_SUPERVISORD_ALERT_FROM}
events=PROCESS_STATE,TICK_60
EOF

  fi
}


# start newrelic if ENV variable TK_NEWRELIC_ENABLED == 1
# newrelic config:
#   TK_NEWRELIC_LICENSE=foobar
#   TK_NEWRELIC_APPNAME=foobar
_init_newrelic() {
  local _newrelic_enableb=${TK_NEWRELIC_ENABLED:-0}
  echo ":: initializing newrelic config (_newrelic_enableb=${_newrelic_enableb})"

  if [[ $_newrelic_enableb == 1 ]] ; then
    local _f_conf="/etc/php/${PHP_VERSION}/mods-available/newrelic.ini"
    local _license=${TK_NEWRELIC_LICENSE:-}
    local _app_name=${TK_NEWRELIC_APPNAME:-tk-nginx-php}

    sed -i "s#newrelic.license = .*#newrelic.license = \"${_license}\"#g" $_f_conf
    sed -i "s#newrelic.appname = .*#newrelic.appname = \"${_app_name}\"#g" $_f_conf

    ln -svf "$_f_conf" /etc/php/${PHP_VERSION}/cli/conf.d/20-newrelic.ini
    ln -svf "$_f_conf" /etc/php/${PHP_VERSION}/fpm/conf.d/20-newrelic.ini
  fi
}

# config td-agent to send log to remote server
# td-agent config:
#   TK_TDAGENT_CENTRAL=fluentd.example.com
#
_init_tdagent(){
  local _tdagent_central=${TK_TDAGENT_CENTRAL:-uat.fluentd.tiki.services}
  local _f_conf="/etc/td-agent/td-agent.conf"
  echo ":: initializing td-agent config (central server: ${_tdagent_central})"
   sed -i "s#host 1.2.3.4#host ${_tdagent_central}#g" $_f_conf
}

# configure telegraf to send metric to time-series db
# telegraf plugin config:
#   INFLUXDB_URL=http://influxdb.env.tiki.services:8086
#
_init_telegraf(){
  local _app_env=${APP_ENV:-local}
  local _influxdb_url=${TK_INFLUXDB_URL}
  local _gcp_sa=${TK_MONITORING_SERVICE_ACCOUNT}
  local _gcp_project="${TK_GCP_MONITORING_PROJECT:-tiki-staging-monitoring}"
  local _f_conf="/etc/telegraf/telegraf.conf"
  local _f_supervisor="/etc/supervisord.conf"

  if [ "$_influxdb_url" != "" ]; then
    echo ":: initializing telegraf config (influxdb url: ${_influxdb_url})"
    mv /etc/telegraf/telegraf.d/influxdb.conf.bak /etc/telegraf/telegraf.d/influxdb.conf
    sed -i "s#{{ influxdb_url }}#${_influxdb_url}#g" /etc/telegraf/telegraf.d/influxdb.conf
  fi
  if [ "$_gcp_sa" != "" ]; then
    echo ":: initializing telegraf config (StackDriver with Services Key Path: ${_gcp_sa} and project_name: ${_gcp_project})"
    sed -i "s#_google_sa_#${_gcp_sa}#g" $_f_supervisor
    mv /etc/telegraf/telegraf.d/stackdriver.conf.bak /etc/telegraf/telegraf.d/stackdriver.conf
    sed -i "s#_gcp_project_name#${_gcp_project}#g" /etc/telegraf/telegraf.d/stackdriver.conf
  fi
  if [[ -z "$_influxdb_url" && -z "$_gcp_sa" ]]; then
    echo "Warning: Non of Influxdb or Stackdriver config is provided !!! Telegraf will not send data"
  fi
}


exec_supervisord() {
    echo 'Start supervisord'
    exec /usr/bin/supervisord -n -c /etc/supervisord.conf
}

# Run helper function if passed as parameters
# Otherwise start supervisord
if [[ -n "$@" ]]; then
  $@
else
  _init_xdebug  # for corveralls.io ...
  _init_opcache
  _init_worker
  _init_superslacker
  _init_newrelic
  _init_tdagent
  _init_telegraf
  exec_supervisord
fi
