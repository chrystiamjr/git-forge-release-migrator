FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Dart SDK (official Google apt repo — supports amd64 and arm64)
RUN wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub \
      | gpg --dearmor -o /usr/share/keyrings/dart.gpg && \
    echo 'deb [signed-by=/usr/share/keyrings/dart.gpg] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main' \
      > /etc/apt/sources.list.d/dart_stable.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends dart && \
    rm -rf /var/lib/apt/lists/*

# Flutter Linux desktop toolchain
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev && \
    rm -rf /var/lib/apt/lists/*
