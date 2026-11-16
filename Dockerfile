FROM swift:6.1-noble AS build
WORKDIR /build
COPY Package.swift Package.resolved ./
RUN swift package resolve
COPY . .
RUN swift build -c release --product GymnasticsClubBackend --static-swift-stdlib

FROM ubuntu:noble
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --create-home --home-dir /app vapor
WORKDIR /app
COPY --from=build --chown=vapor:vapor /build/.build/release/GymnasticsClubBackend /app/GymnasticsClubBackend
ENV SWIFT_BACKTRACE=enable=yes,sanitize=yes,threads=all,images=all,interactive=no
USER vapor:vapor
EXPOSE 8080
ENTRYPOINT ["/app/GymnasticsClubBackend"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
