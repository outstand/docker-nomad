#!/usr/bin/dumb-init /bin/sh
set -e

# Note above that we run dumb-init as PID 1 in order to reap zombie processes
# as well as forward signals to all processes in its session. Normally, sh
# wouldn't do either of these functions so we'd leak zombies as well as do
# unclean termination of all our sub-processes.

# Nomad's docker driver needs access to the docker socket.  We don't know what
# the gid of the docker group in the host is so we figure it out here.
if [ -S /var/run/docker.sock ]; then
  usermod -a -G $(stat -c '%g' /var/run/docker.sock) nomad
fi

# This exposes three different modes, and allows for the execution of arbitrary
# commands if one of these modes isn't chosen. Each of the modes will read from
# the config directory, allowing for easy customization by placing JSON files
# there. Note that there's a common config location, as well as one specifc to
# the server and agent modes.
NOMAD_DATA_DIR=/nomad/data
NOMAD_CONFIG_DIR=/nomad/config
if [ "$1" = 'dev' ]; then
    shift
    gosu nomad \
        nomad agent \
         -dev \
         -config="$NOMAD_CONFIG_DIR/local" \
         "$@"
elif [ "$1" = 'client' ]; then
    shift
    gosu nomad \
        nomad agent \
         -client \
         -data-dir="$NOMAD_DATA_DIR" \
         -config="$NOMAD_CONFIG_DIR/client" \
         -config="$NOMAD_CONFIG_DIR/local" \
         "$@"
elif [ "$1" = 'server' ]; then
    shift
    gosu nomad \
        nomad agent \
         -server \
         -data-dir="$NOMAD_DATA_DIR" \
         -config="$NOMAD_CONFIG_DIR/server" \
         -config="$NOMAD_CONFIG_DIR/local" \
         "$@"
else
    exec "$@"
fi

# If nomad exits then kill everything else.
kill -TERM 1
