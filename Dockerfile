# Build stage
FROM golang:1.27.0-trixie AS builder

WORKDIR /build

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the binary
RUN go build -o claude-tools-mcp ./cmd/claude-tools-mcp

# Runtime stage - use pre-built runtime image from GHCR
# To build locally without GHCR, first tag the runtime image to match this FROM.
# docker build -f Dockerfile.runtime -t ghcr.io/mathematic-inc/claude-tools-mcp-runtime:latest .
# hadolint ignore=DL3007
FROM ghcr.io/mathematic-inc/claude-tools-mcp-runtime:latest

# Switch to root to copy binary
USER 0

# Copy the binary from builder
COPY --from=builder /build/claude-tools-mcp /usr/local/bin/claude-tools-mcp

# Expose HTTP port
EXPOSE 8080

# Switch back to non-root user
USER 1000

# Start the MCP server - use PORT env var if set, otherwise default to 8080
CMD ["/bin/sh", "-c", "/usr/local/bin/claude-tools-mcp --addr 0.0.0.0:${PORT:-8080}"]
