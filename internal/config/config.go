package config

import (
	"strings"

	"github.com/spf13/viper"
)

// Config represents the application configuration structure.
type Config struct {
	Server struct {
		Port string `mapstructure:"port"`
	} `mapstructure:"server"`
	Log struct {
		Level string `mapstructure:"level"`
	} `mapstructure:"log"`
	Environment string `mapstructure:"environment"`
}

// LoadConfig loads configuration from config.yaml and environment variables.
func LoadConfig() (*Config, error) {
	viper.SetConfigName("config")
	viper.SetConfigType("json")
	viper.AddConfigPath(".")

	// Support environment variables
	viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
	viper.AutomaticEnv()

	// Default values
	viper.SetDefault("server.port", "8080")
	viper.SetDefault("log.level", "info")
	viper.SetDefault("environment", "development")

	if err := viper.ReadInConfig(); err != nil {
		// It's fine if config.yaml is not found, we fallback to defaults / env vars
		if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
			return nil, err
		}
	}

	var cfg Config
	if err := viper.Unmarshal(&cfg); err != nil {
		return nil, err
	}

	return &cfg, nil
}
