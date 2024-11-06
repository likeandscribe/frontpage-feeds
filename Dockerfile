FROM rust:1-bookworm AS build

RUN cargo install sqlx-cli@0.8.2 --no-default-features --features sqlite
RUN cargo install sccache --version ^0.8
ENV RUSTC_WRAPPER=sccache SCCACHE_DIR=/sccache

RUN curl https://github.com/astrenoxcoop/supercell/archive/refs/tags/0.1.2.zip -L -o supercell.zip && unzip supercell.zip

RUN mv supercell-0.1.2 /app

WORKDIR /app

RUN curl https://github.com/bluesky-social/jetstream/raw/0ab10bd041fe1fdf682d3964b20d944905c4862d/pkg/models/zstd_dictionary -L -o ./jetstream_zstd_dictionary

RUN --mount=type=cache,target=/app/target/ \
  --mount=type=cache,target=$SCCACHE_DIR,sharing=locked \
  --mount=type=cache,target=/usr/local/cargo/registry/ \
  <<EOF
set -e
cargo build --release --bin supercell --target-dir .
EOF

FROM debian:bookworm-slim

RUN set -x \
  && apt-get update \
  && apt-get install ca-certificates -y

RUN groupadd -g 1508 -r supercell && useradd -u 1509 -r -g supercell -d /var/lib/supercell -m supercell

ENV RUST_LOG=info
ENV RUST_BACKTRACE=full
ENV DATABASE_URL=sqlite:///var/lib/supercell/db/db.db?mode=rwc
ENV ZSTD_DICTIONARY=/var/lib/supercell/jetstream_zstd_dictionary

COPY ./config.yml /var/lib/supercell/config.yml
COPY --from=build /app/release/supercell /var/lib/supercell/
COPY --from=build /app/jetstream_zstd_dictionary /var/lib/supercell/

RUN mkdir -p /var/lib/supercell/db

RUN chown -R supercell:supercell /var/lib/supercell

WORKDIR /var/lib/supercell

USER supercell
ENTRYPOINT ["sh", "-c", "/var/lib/supercell/supercell"]
