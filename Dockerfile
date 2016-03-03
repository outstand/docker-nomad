FROM buildpack-deps:jessie-curl
# alpine doesn't current work due to https://bugs.alpinelinux.org/issues/5130
#FROM frolvlad/alpine-glibc
MAINTAINER Ryan Schlesinger <ryan@outstand.com>

# Comment out for alpine
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales \
    unzip \
    socat \
  && rm -rf /var/lib/apt/lists/*

# This is the release of Consul to pull in.
ENV NOMAD_VERSION=0.3.0
ENV NOMAD_SHA256SUM=530e5177cecd65d36102953099db19ecdbfa62b3acf20a0c48e20753a597f28e

# This is the release of https://github.com/hashicorp/docker-base to pull in order
# to provide HashiCorp-built versions of basic utilities like dumb-init and gosu.
ENV DOCKER_BASE_VERSION=0.0.4
ENV DOCKER_BASE_SHA256SUM=5262aa8379782d42f58afbda5af884b323ff0b08a042e7915eb1648891a8da00

# Create a nomad user and group first so the IDs get set the same way, even as
# the rest of this may change over time.
# RUN addgroup nomad && \
#     adduser -S -G nomad nomad
# Comment out for alpine
RUN useradd -ms /bin/bash nomad

# Set up certificates, our base tools, and Nomad.
# uncomment for alpine
#RUN apk add --no-cache ca-certificates socat && \
RUN    cd /tmp && \
    wget -O docker-base.zip https://releases.hashicorp.com/docker-base/${DOCKER_BASE_VERSION}/docker-base_${DOCKER_BASE_VERSION}_linux_amd64.zip && \
    echo "${DOCKER_BASE_SHA256SUM}  docker-base.zip" | sha256sum -c && \
    unzip -d / docker-base.zip && \
    rm docker-base.zip && \
    wget -O nomad.zip https://releases.hashicorp.com/nomad/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_linux_amd64.zip && \
    echo "${NOMAD_SHA256SUM}  nomad.zip" | sha256sum -c && \
    unzip -d /bin nomad.zip && \
    rm nomad.zip

# The /nomad/data dir is used by Nomad to store state. The agent will be started
# with /nomad/config/local as the configuration directory so you can add additional
# config files in that location. There are client and server-specific locations so
# we can supply some default configs via this base image as well.
RUN mkdir -p /nomad/data && \
    mkdir -p /nomad/config/local && \
    mkdir -p /nomad/config/client && \
    mkdir -p /nomad/config/server && \
    chown -R nomad:nomad /nomad

# Client mode has some default configuration that's good for running in containers,
# namely agents will leave the cluster if you stop the container. This isn't
# usually desirable for servers so we don't include it there.
COPY client.json /nomad/config/client/

# Expose the nomad data directory as a volume since there's mutable state in there.
VOLUME /nomad/data

# HTTP
EXPOSE 4646

# Server RPC
EXPOSE 4647

# Serf
EXPOSE 4648 4648/udp

# Nomad doesn't need root privileges so we run it as the nomad user from the
# entry point script. The entry point script also uses dumb-init as the top-level
# process to reap any zombie processes created by Nomad sub-processes.
COPY entrypoint.sh /
ENV DUMB_INIT_SETSID 0
ENTRYPOINT ["/entrypoint.sh"]

# By default you'll get a single-node development server that stores everything
# in RAM, exposes a web UI, and bootstraps itself. Don't use this configuration
# for production.
CMD ["dev"]
