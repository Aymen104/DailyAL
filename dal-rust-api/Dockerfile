FROM rust:1.85.1 as builder

WORKDIR /builder

COPY . .

RUN cargo update -p jsonwebtoken --precise 9.2.0

RUN cargo build -p dal-rust-api --release

FROM gcr.io/distroless/cc

COPY --from=builder /builder/target/release/dal-rust-api /

EXPOSE 8001

CMD ["./dal-rust-api"]