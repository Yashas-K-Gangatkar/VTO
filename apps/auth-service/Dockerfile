# syntax=docker/dockerfile:1.6

FROM golang:1.22-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download || true

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /auth-service ./cmd/server

RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /create-api-key ./cmd/create-api-key

FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=builder /auth-service /auth-service
COPY --from=builder /create-api-key /create-api-key

USER nonroot
EXPOSE 8081

ENTRYPOINT ["/auth-service"]
