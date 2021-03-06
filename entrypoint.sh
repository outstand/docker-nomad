#!/bin/dumb-init /bin/sh
set -e

# Note above that we run dumb-init as PID 1 in order to reap zombie processes
# as well as forward signals to all processes in its session. Normally, sh
# wouldn't do either of these functions so we'd leak zombies as well as do
# unclean termination of all our sub-processes.

# We need to find the bind address if instructed to bind to an interface
NOMAD_BIND=
if [ -n "$NOMAD_BIND_INTERFACE" ]; then
  NOMAD_BIND_ADDRESS=$(ip -o -4 addr list $NOMAD_BIND_INTERFACE | awk '{print $4}' | cut -d/ -f1)
  if [ -z "$NOMAD_BIND_ADDRESS" ]; then
    echo "Network interface $NOMAD_BIND_INTERFACE has no ip address, exiting."
    exit 1
  fi
  NOMAD_BIND="-bind=$NOMAD_BIND_ADDRESS -network-interface=$NOMAD_BIND_INTERFACE"
fi

NOMAD_DATA_DIR=/nomad/data
NOMAD_CONFIG_DIR=/nomad/config

if [ -n "$NOMAD_HTTP_ADDRESS" ]; then
  cat > $NOMAD_CONFIG_DIR/local/http_address.hcl <<EOF
addresses {
  http = "$NOMAD_HTTP_ADDRESS"
}
EOF
fi

NOMAD_SERVERS_OPT=
if [ -n "$NOMAD_SERVERS" ]; then
  NOMAD_SERVERS_OPT="-servers=$NOMAD_SERVERS"
fi

if [ -n "$NOMAD_REQUIRE_DOCKER" ] && [ ! -S /var/run/docker.sock ]; then
  echo 'Docker socket not found, exiting.'
  exit 1
fi

# Nomad's docker driver needs access to the docker socket.  We don't know what
# the gid of the docker group in the host is so we figure it out here.
if [ -S /var/run/docker.sock ]; then
  GID=$(stat -c '%g' /var/run/docker.sock)
  # Ensure the group exists
  if ! getent group $GID; then
    groupadd -g $GID docker
  fi
  usermod -a -G $GID nomad

  # Guarantee that we can talk to docker or nomad will start anyway
  # but won't be able to do anything.
  socat - UNIX-CONNECT:/var/run/docker.sock >/dev/null <<EOF
GET /info HTTP/1.1

EOF
  if [ $? -ne 0 ]; then
    echo 'Failed to connect to /var/run/docker.sock, exiting.'
    exit 1
  fi
fi


# This exposes three different modes, and allows for the execution of arbitrary
# commands if one of these modes isn't chosen. Each of the modes will read from
# the config directory, allowing for easy customization by placing JSON files
# there. Note that there's a common config location, as well as one specifc to
# the server and agent modes.
if [ "$1" = 'dev' ]; then
    shift
    gosu nomad \
        nomad agent \
         -dev \
         -config="$NOMAD_CONFIG_DIR/local" \
         $NOMAD_BIND \
         "$@"
elif [ "$1" = 'client' ]; then
    shift
    gosu nomad \
        nomad agent \
         -client \
         -data-dir="$NOMAD_DATA_DIR" \
         -config="$NOMAD_CONFIG_DIR/client" \
         -config="$NOMAD_CONFIG_DIR/local" \
         $NOMAD_BIND \
         $NOMAD_SERVERS_OPT \
         "$@"
elif [ "$1" = 'server' ]; then
    shift
    gosu nomad \
        nomad agent \
         -server \
         -data-dir="$NOMAD_DATA_DIR" \
         -config="$NOMAD_CONFIG_DIR/server" \
         -config="$NOMAD_CONFIG_DIR/local" \
         $NOMAD_BIND \
         "$@"
else
    exec "$@"
fi
