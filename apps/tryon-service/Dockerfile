# syntax=docker/dockerfile:1.6

FROM golang:1.22-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download || true

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /tryon-service ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=builder /tryon-service /tryon-service

USER nonroot
EXPOSE 8084

ENTRYPOINT ["/tryon-service"]
