FROM buildpack-deps:jessie-curl
MAINTAINER Ryan Schlesinger <ryan@outstand.com>

RUN apt-get update && apt-get install -y --no-install-recommends \
    locales \
    unzip \
    socat \
  && rm -rf /var/lib/apt/lists/*

# grab gosu for easy step-down from root
RUN gpg --keyserver pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4
RUN curl -o /usr/local/bin/gosu -SL "https://github.com/tianon/gosu/releases/download/1.7/gosu-$(dpkg --print-architecture)" \
  && curl -o /usr/local/bin/gosu.asc -SL "https://github.com/tianon/gosu/releases/download/1.7/gosu-$(dpkg --print-architecture).asc" \
  && gpg --verify /usr/local/bin/gosu.asc \
  && rm /usr/local/bin/gosu.asc \
  && chmod +x /usr/local/bin/gosu

RUN wget https://github.com/Yelp/dumb-init/releases/download/v1.0.0/dumb-init_1.0.0_amd64.deb
RUN dpkg -i dumb-init_*.deb

RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Create a nomad user and group first so the IDs get set the same way, even as
# the rest of this may change over time.
RUN useradd -ms /bin/bash nomad

# Pull down the Nomad binary. BusyBox has a non-SSL capable wget so we use the host
# to fetch the file and verify inside the container.
ENV NOMAD_SHA256 0f3a7083d160893a291b5f8b4359683c2df7991fa0a3e969f8785ddb40332a8c
ADD https://releases.hashicorp.com/nomad/0.2.3/nomad_0.2.3_linux_amd64.zip /nomad.zip

# Pull down and verify the nomad binary.
RUN set -x && \
    echo "${NOMAD_SHA256}  nomad.zip" | sha256sum -c - && \
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
