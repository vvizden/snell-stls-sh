ARG DISTRO=debian:12
FROM ${DISTRO}
ENV container=docker
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    systemd systemd-sysv dbus bash ca-certificates curl unzip zip jq file openssl util-linux iproute2 coreutils passwd \
    && rm -rf /var/lib/apt/lists/*
COPY snell.sh /src/snell.sh
COPY tests /src/tests
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
