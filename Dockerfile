# Stage 1: Build
FROM rust:1.82-alpine AS builder

RUN apk add --no-cache musl-dev

WORKDIR /app
COPY Cargo.toml ./
COPY src ./src

RUN cargo build --release --bin eso-demo

# Stage 2: Runtime (minimal image)
FROM alpine:3.20

RUN apk add --no-cache ca-certificates

COPY --from=builder /app/target/release/eso-demo /usr/local/bin/eso-demo

USER nobody
ENTRYPOINT ["/usr/local/bin/eso-demo"]
