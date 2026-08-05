package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/mathematic-inc/claude-tools-mcp/internal/tools"
	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/spf13/cobra"
)

const (
	version                  = "0.1.0"
	defaultAddr              = "localhost:8080"
	defaultReadHeaderTimeout = 10 * time.Second
	defaultIdleTimeout       = 120 * time.Second
	defaultShutdownTimeout   = 10 * time.Second
)

var (
	addr    string
	token   string
	rootCmd = &cobra.Command{
		Use:     "claude-tools-mcp",
		Short:   "Claude Tools MCP Server",
		Long:    "This server exposes the same tools available in Claude Code, allowing them to be used by other MCP clients.",
		Version: version,
		RunE:    runServer,
	}
)

func init() {
	rootCmd.Flags().StringVarP(&addr, "addr", "a", defaultAddr, "Server address (host:port)")
	rootCmd.Flags().StringVar(&token, "token", "", "Bearer token required for all requests (empty = no auth)")
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

// requireToken wraps an HTTP handler with bearer token authentication. When
// token is empty, the handler is returned unchanged and auth is disabled.
func requireToken(next http.Handler, token string) http.Handler {
	if token == "" {
		return next
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.EqualFold(r.Header.Get("Authorization"), "Bearer "+token) {
			w.WriteHeader(http.StatusUnauthorized)
			fmt.Fprintln(w, "unauthorized")
			return
		}
		next.ServeHTTP(w, r)
	})
}

// setupHTTPServer creates an HTTP server with the MCP handler and security timeouts
// configured to prevent slowloris attacks and resource exhaustion.
func setupHTTPServer(addr string, mcpHandler http.Handler) *http.Server {
	mux := http.NewServeMux()
	mux.Handle("/", mcpHandler)
	return &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: defaultReadHeaderTimeout,
		IdleTimeout:       defaultIdleTimeout,
	}
}

func runServer(cmd *cobra.Command, args []string) error {
	// Set up graceful shutdown context that responds to SIGINT and SIGTERM,
	// allowing in-flight requests to complete before stopping the server.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// Initialize MCP server with tool definitions.
	mcpServer := mcp.NewServer(&mcp.Implementation{
		Name:    "claude-tools",
		Version: version,
	}, nil)

	// Register all available tools.
	mcp.AddTool(mcpServer, &tools.BashTool, tools.Bash)
	mcp.AddTool(mcpServer, &tools.BashOutputTool, tools.BashOutput)
	mcp.AddTool(mcpServer, &tools.ListShellsTool, tools.ListShells)
	mcp.AddTool(mcpServer, &tools.KillShellTool, tools.KillShell)
	mcp.AddTool(mcpServer, &tools.ReadTool, tools.Read)
	mcp.AddTool(mcpServer, &tools.WriteTool, tools.Write)
	mcp.AddTool(mcpServer, &tools.EditTool, tools.Edit)
	mcp.AddTool(mcpServer, &tools.GlobTool, tools.Glob)
	mcp.AddTool(mcpServer, &tools.GrepTool, tools.Grep)

	// Stateless mode allows each HTTP request to be handled independently without
	// session state, enabling horizontal scaling and simpler request handling.
	mcpHandler := mcp.NewStreamableHTTPHandler(func(r *http.Request) *mcp.Server {
		return mcpServer
	}, &mcp.StreamableHTTPOptions{
		Stateless: true,
	})

	server := setupHTTPServer(addr, requireToken(mcpHandler, token))

	// Run server in goroutine to allow concurrent shutdown handling via select.
	errCh := make(chan error, 1)
	go func() {
		fmt.Printf("MCP server listening on http://%s\n", addr)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			errCh <- fmt.Errorf("HTTP server error: %w", err)
		}
	}()

	// Wait for either server error or shutdown signal.
	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
		fmt.Println("\nShutting down server...")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), defaultShutdownTimeout)
		defer cancel()
		if err := server.Shutdown(shutdownCtx); err != nil {
			return fmt.Errorf("server shutdown error: %w", err)
		}
		fmt.Println("Server stopped gracefully")
	}
	return nil
}
