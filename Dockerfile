# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Stage 1: Build — compile gfrm to a native AOT binary
# ---------------------------------------------------------------------------
FROM dart:3.11.0 AS builder

WORKDIR /app

# Cache pub dependencies separately from source
COPY dart_cli/pubspec.yaml dart_cli/pubspec.lock ./dart_cli/
RUN cd dart_cli && dart pub get --no-example

# Copy source and compile
COPY dart_cli/ ./dart_cli/
RUN mkdir -p dart_cli/build && \
    dart compile exe dart_cli/bin/gfrm_dart.dart -o dart_cli/build/gfrm

# ---------------------------------------------------------------------------
# Stage 2: Run — minimal image with the compiled binary
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim AS runner

# dio (HTTP client) requires libssl; TLS to GitHub/GitLab/Bitbucket requires ca-certificates
RUN apt-get update && \
    apt-get install -y --no-install-recommends libssl3 ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/dart_cli/build/gfrm /usr/local/bin/gfrm

# migration-results/ and sessions/ are written at runtime — mount these as volumes
VOLUME ["/app/migration-results", "/app/sessions"]

ENTRYPOINT ["gfrm"]
CMD ["--help"]
