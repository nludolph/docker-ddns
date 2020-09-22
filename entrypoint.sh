#!/bin/bash
set -e

[ -z "$SHARED_SECRET" ] && echo "SHARED_SECRET not set" && exit 1;
[ -z "$ZONE" ] && echo "ZONE not set" && exit 1;
[ -z "$RECORD_TTL" ] && echo "RECORD_TTL not set" && exit 1;

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
  local var="$1"
  local fileVar="${var}_FILE"
  local def="${2:-}"
  if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
    echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
    exit 1
  fi
  local val="$def"
  if [ "${!var:-}" ]; then
    val="${!var}"
  elif [ "${!fileVar:-}" ]; then
    val="$(< "${!fileVar}")"
  fi
  export "$var"="$val"
  unset "$fileVar"
}

BIND_DATA_DIR=${DATA_DIR}/bind

create_bind_data_dir() {
  mkdir -p ${BIND_DATA_DIR}

  # populate default bind configuration if it does not exist
  if [ ! -d ${BIND_DATA_DIR}/etc ]; then
    mv /etc/bind ${BIND_DATA_DIR}/etc
  fi
  rm -rf /etc/bind
  ln -sf ${BIND_DATA_DIR}/etc /etc/bind
  chmod -R 0775 ${BIND_DATA_DIR}
  chown -R ${BIND_USER}:${BIND_USER} ${BIND_DATA_DIR}

  if [ ! -d ${BIND_DATA_DIR}/lib ]; then
    mkdir -p ${BIND_DATA_DIR}/lib
    chown ${BIND_USER}:${BIND_USER} ${BIND_DATA_DIR}/lib
  fi
  rm -rf /var/lib/bind
  ln -sf ${BIND_DATA_DIR}/lib /var/lib/bind
}

create_pid_dir() {
  mkdir -p /var/run/named
  chmod 0775 /var/run/named
  chown root:${BIND_USER} /var/run/named
}

create_bind_cache_dir() {
  mkdir -p /var/cache/bind
  chmod 0775 /var/cache/bind
  chown root:${BIND_USER} /var/cache/bind
}

check_and_add_zone() {
  if ! grep 'zone "'$ZONE'"' /etc/bind/named.conf.local > /dev/null
  then
    echo "creating zone...";
    cat >> /etc/bind/named.conf.local <<EOF
zone "$ZONE" {
  type master;
  file "/etc/bind/$ZONE.zone";
  allow-query { any; };
  allow-transfer { none; };
  allow-update { localhost; };
};
EOF
  fi

  if [ ! -f /etc/bind/$ZONE.zone ]
  then
    echo "creating zone file..."
    cat > /etc/bind/$ZONE.zone <<EOF
\$ORIGIN .
\$TTL 86400	; 1 day
$ZONE		IN SOA	localhost. root.localhost. (
        74         ; serial
        3600       ; refresh (1 hour)
        900        ; retry (15 minutes)
        604800     ; expire (1 week)
        86400      ; minimum (1 day)
        )
      NS	localhost.
\$ORIGIN ${ZONE}.
\$TTL ${RECORD_TTL}
EOF
  fi
}

check_and_add_ddnsJson() {
  if [ ! -f /etc/dyndns.json ]
  then
    echo "creating REST api config..."
    cat > /etc/dyndns.json <<EOF
{
    "SharedSecret": "${SHARED_SECRET}",
    "Server": "localhost",
    "Zone": "${ZONE}.",
    "Domain": "${ZONE}",
    "NsupdateBinary": "/usr/bin/nsupdate",
	"RecordTTL": ${RECORD_TTL}
}
EOF
  fi
}

create_pid_dir
create_bind_data_dir
create_bind_cache_dir
check_and_add_zone
check_and_add_ddnsJson

# allow arguments to be passed to named
if [[ ${1:0:1} = '-' ]]; then
  EXTRA_ARGS="$*"
  set --
elif [[ ${1} == named || ${1} == "$(command -v named)" ]]; then
  EXTRA_ARGS="${*:2}"
  set --
fi

echo "Starting ddns..."
/root/dyndns &

# default behaviour is to launch named
if [[ -z ${1} ]]; then
  echo "Starting named..."
  exec "$(command -v named)" -u ${BIND_USER} -g ${EXTRA_ARGS}
else
  exec "$@"
fi
