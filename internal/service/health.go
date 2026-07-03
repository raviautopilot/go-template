package service

import (
	"time"

	"github.com/raviautopilot/go-template/internal/config"
	"go.uber.org/zap"
)

// HealthResponse represents the business logic output of the health check.
type HealthResponse struct {
	Status    string
	Timestamp string
}

// HealthService defines the business logic contract for health check.
type HealthService interface {
	CheckHealth() *HealthResponse
}

type healthService struct {
	cfg *config.Config
	log *zap.Logger
}

// NewHealthService creates a new instance of HealthService.
func NewHealthService(cfg *config.Config, log *zap.Logger) HealthService {
	return &healthService{
		cfg: cfg,
		log: log,
	}
}

// CheckHealth returns the current status and timestamp of the service.
func (s *healthService) CheckHealth() *HealthResponse {
	s.log.Debug("Executing health check business logic")
	return &HealthResponse{
		Status:    "UP",
		Timestamp: time.Now().Format(time.RFC3339),
	}
}
