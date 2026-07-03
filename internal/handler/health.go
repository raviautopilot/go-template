package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"

	"github.com/raviautopilot/go-template/internal/config"
	"github.com/raviautopilot/go-template/internal/service"
)

// HealthResponse represents the response structure of the health endpoint.
type HealthResponse struct {
	Status    string `json:"status" example:"UP"`
	Timestamp string `json:"timestamp" example:"2026-07-04T01:07:40+05:30"`
}

// HealthHandler handles the health check requests.
type HealthHandler struct {
	cfg           *config.Config
	log           *zap.Logger
	healthService service.HealthService
}

// NewHealthHandler creates a new instance of HealthHandler.
func NewHealthHandler(cfg *config.Config, log *zap.Logger, hs service.HealthService) *HealthHandler {
	return &HealthHandler{
		cfg:           cfg,
		log:           log,
		healthService: hs,
	}
}

// Health handles the health check request.
// @Summary      Health Check
// @Description  Get the health status of the microservice
// @Tags         System
// @Produce      json
// @Success      200  {object}  HealthResponse
// @Router       /health [get]
func (h *HealthHandler) Health(c *gin.Context) {
	serviceResp := h.healthService.CheckHealth()
	resp := HealthResponse{
		Status:    serviceResp.Status,
		Timestamp: serviceResp.Timestamp,
	}
	c.JSON(http.StatusOK, resp)
}
