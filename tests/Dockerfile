FROM debian:12
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    bash ca-certificates curl unzip zip jq file openssl util-linux iproute2 coreutils passwd shellcheck \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY snell.sh /src/snell.sh
COPY tests /src/tests
CMD ["bash", "tests/run.sh"]
