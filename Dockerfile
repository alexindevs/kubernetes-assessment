# Build stage
FROM golang:1.25.1-alpine AS builder

WORKDIR /app

COPY Server/MuchToDo/go.mod Server/MuchToDo/go.sum ./
RUN go mod download

# Copy source code
COPY Server/MuchToDo/ ./

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o muchtodo ./cmd/api

# Runtime stage
FROM alpine:latest

# Install ca-certificates for HTTPS
RUN apk --no-cache add ca-certificates

WORKDIR /app

# Create non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copy binary from builder
COPY --from=builder /app/muchtodo .

# Change ownership to non-root user
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Write runtime config where the app expects it, then start the binary.
CMD ["/bin/sh", "-c", "cat > /app/.env <<EOF\nPORT=${PORT}\nMONGO_URI=${MONGO_URI}\nDB_NAME=${DB_NAME}\nJWT_SECRET_KEY=${JWT_SECRET_KEY}\nJWT_EXPIRATION_HOURS=${JWT_EXPIRATION_HOURS:-72}\nENABLE_CACHE=${ENABLE_CACHE:-false}\nREDIS_ADDR=${REDIS_ADDR}\nREDIS_PASSWORD=${REDIS_PASSWORD}\nLOG_LEVEL=${LOG_LEVEL}\nLOG_FORMAT=${LOG_FORMAT}\nEOF\nexec ./muchtodo"]
