package router

import (
	"github.com/gin-gonic/gin"
	swaggerFiles "github.com/swaggo/files"
	ginSwagger "github.com/swaggo/gin-swagger"
	"go.uber.org/zap"

	_ "github.com/raviautopilot/go-template/docs"
	"github.com/raviautopilot/go-template/internal/config"
	"github.com/raviautopilot/go-template/internal/handler"
	"github.com/raviautopilot/go-template/internal/logger"
)

// NewRouter initializes Gin engine with middlewares and routes.
func NewRouter(cfg *config.Config, log *zap.Logger, healthHandler *handler.HealthHandler) *gin.Engine {
	if cfg.Environment == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	r := gin.New()

	// Use our custom Zap middlewares
	r.Use(logger.GinZap(log))
	r.Use(logger.GinRecovery(log))

	// Register Routes
	r.GET("/health", healthHandler.Health)

	// Serve Swagger UI
	r.GET("/swagger/*any", ginSwagger.WrapHandler(swaggerFiles.Handler))

	return r
}
