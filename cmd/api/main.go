package main

import (
	"context"
	"errors"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"go.uber.org/zap"

	"github.com/raviautopilot/go-template/internal/config"
	"github.com/raviautopilot/go-template/internal/handler"
	"github.com/raviautopilot/go-template/internal/logger"
	"github.com/raviautopilot/go-template/internal/router"
	"github.com/raviautopilot/go-template/internal/service"
)

// @title           Go Microservice Boilerplate API
// @version         1.0
// @description     This is a production-ready boilerplate Go microservice API.
// @termsOfService  http://swagger.io/terms/

// @contact.name   API Support
// @contact.url    http://www.swagger.io/support
// @contact.email  support@swagger.io

// @license.name  Apache 2.0
// @license.url   http://www.apache.org/licenses/LICENSE-2.0.html

// @host      localhost:8080
// @BasePath  /
func main() {
	// 1. Load Configuration
	cfg := loadConfig()

	// 2. Initialize Zap Logger
	log := initLogger(cfg)
	defer syncLogger(log)

	log.Info("Starting application",
		zap.String("environment", cfg.Environment),
		zap.String("port", cfg.Server.Port),
	)

	// 3. Initialize layers (Dependency Injection)
	healthHandler := initDependencies(cfg, log)

	// 4. Configure Gin Router
	r := initRouter(cfg, log, healthHandler)

	// 5. Graceful Shutdown Implementation
	runServerWithGracefulShutdown(cfg, log, r)
}

// loadConfig loads application configuration
func loadConfig() *config.Config {
	cfg, err := config.LoadConfig()
	if err != nil {
		panic("Failed to load configuration: " + err.Error())
	}
	return cfg
}

// initLogger initializes Zap logger with configuration
func initLogger(cfg *config.Config) *zap.Logger {
	log, err := logger.InitLogger(cfg.Log.Level, cfg.Environment)
	if err != nil {
		panic("Failed to initialize logger: " + err.Error())
	}
	return log
}

// syncLogger flushes any buffered log entries
func syncLogger(log *zap.Logger) {
	// Sync is called to flush any buffered log entries.
	// Ignore any error as syncing can fail on stdout/stderr on some OS/platforms.
	_ = log.Sync()
}

// initDependencies initializes all application layers (Dependency Injection)
func initDependencies(cfg *config.Config, log *zap.Logger) *handler.HealthHandler {
	healthService := service.NewHealthService(cfg, log)
	return handler.NewHealthHandler(cfg, log, healthService)
}

// initRouter configures and returns the Gin router
func initRouter(cfg *config.Config, log *zap.Logger, healthHandler *handler.HealthHandler) http.Handler {
	return router.NewRouter(cfg, log, healthHandler)
}

// runServerWithGracefulShutdown starts the server and handles graceful shutdown
func runServerWithGracefulShutdown(cfg *config.Config, log *zap.Logger, handler http.Handler) {
	srv := &http.Server{
		Addr:    ":" + cfg.Server.Port,
		Handler: handler,
	}

	// Initializing the server in a goroutine so that
	// it won't block the graceful shutdown handling below
	go func() {
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatal("Listen error", zap.Error(err))
		}
	}()

	// Wait for interrupt signal to gracefully shutdown the server with
	// a timeout of 5 seconds.
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Info("Shutting down server...")

	// The context is used to inform the server it has 5 seconds to finish
	// the request it is currently handling
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Fatal("Server forced to shutdown", zap.Error(err))
	}

	log.Info("Server exiting gracefully")
}
