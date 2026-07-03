package main

import (
	"context"
	"errors"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	swaggerFiles "github.com/swaggo/files"
	ginSwagger "github.com/swaggo/gin-swagger"
	"go.uber.org/zap"

	// Swagger generated docs package
	_ "github.com/raviautopilot/go-template/docs"
	"github.com/raviautopilot/go-template/internal/config"
	"github.com/raviautopilot/go-template/internal/handlers"
	"github.com/raviautopilot/go-template/internal/logger"
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
	cfg, err := config.LoadConfig()
	if err != nil {
		panic("Failed to load configuration: " + err.Error())
	}

	// 2. Initialize Zap Logger
	if err := logger.InitLogger(cfg.Log.Level, cfg.Environment); err != nil {
		panic("Failed to initialize logger: " + err.Error())
	}
	defer func() {
		// Sync is called to flush any buffered log entries.
		// Ignore any error as syncing can fail on stdout/stderr on some OS/platforms.
		_ = logger.Log.Sync()
	}()

	logger.Log.Info("Starting application",
		zap.String("environment", cfg.Environment),
		zap.String("port", cfg.Server.Port),
	)

	// 3. Configure Gin Router
	if cfg.Environment == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	r := gin.New()

	// Use our custom Zap middlewares
	r.Use(logger.GinZap())
	r.Use(logger.GinRecovery())

	// 4. Register Routes
	r.GET("/health", handlers.HealthHandler)

	// Serve Swagger UI
	r.GET("/swagger/*any", ginSwagger.WrapHandler(swaggerFiles.Handler))

	// 5. Graceful Shutdown Implementation
	srv := &http.Server{
		Addr:    ":" + cfg.Server.Port,
		Handler: r,
	}

	// Initializing the server in a goroutine so that
	// it won't block the graceful shutdown handling below
	go func() {
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Log.Fatal("Listen error", zap.Error(err))
		}
	}()

	// Wait for interrupt signal to gracefully shutdown the server with
	// a timeout of 5 seconds.
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	logger.Log.Info("Shutting down server...")

	// The context is used to inform the server it has 5 seconds to finish
	// the request it is currently handling
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		logger.Log.Fatal("Server forced to shutdown", zap.Error(err))
	}

	logger.Log.Info("Server exiting gracefully")
}
