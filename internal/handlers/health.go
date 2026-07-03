package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// HealthResponse represents the response structure of the health endpoint.
type HealthResponse struct {
	Status    string `json:"status" example:"UP"`
	Timestamp string `json:"timestamp" example:"2026-07-04T01:07:40+05:30"`
}

// HealthHandler handles the health check request.
// @Summary      Health Check
// @Description  Get the health status of the microservice
// @Tags         System
// @Produce      json
// @Success      200  {object}  HealthResponse
// @Router       /health [get]
func HealthHandler(c *gin.Context) {
	resp := HealthResponse{
		Status:    "UP",
		Timestamp: time.Now().Format(time.RFC3339),
	}
	c.JSON(http.StatusOK, resp)
}
