FROM golang:1.25-alpine AS builder

WORKDIR /build

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /app ./cmd/api/main.go

FROM gcr.io/distroless/static-debian12

COPY --from=builder /app /app

EXPOSE 8080
USER nonroot:nonroot

ENTRYPOINT ["/app"]
