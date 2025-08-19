# Enigmo Server - Production Dockerfile
# Multi-stage build for optimal image size and security

# Build stage
FROM dart:stable AS builder

# Set working directory
WORKDIR /app

# Copy pubspec files first for better layer caching
COPY pubspec.yaml pubspec.lock ./

# Install dependencies
RUN dart pub get

# Copy source code
COPY . .

# Compile to native executable
RUN dart compile exe bin/anongram_server.dart -o enigmo-server

# Production stage
FROM debian:stable-slim AS runtime

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create app user for security
RUN useradd -r -s /bin/false enigmo

# Set working directory
WORKDIR /app

# Copy compiled executable from builder stage
COPY --from=builder /app/enigmo-server ./enigmo-server

# Change ownership to app user
RUN chown enigmo:enigmo ./enigmo-server

# Switch to app user
USER enigmo

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/api/health || exit 1

# Set environment variables
ENV DART_ENV=production
ENV HOST=0.0.0.0
ENV PORT=8080

# Run the server
CMD ["./enigmo-server", "--host", "0.0.0.0", "--port", "8080"]
