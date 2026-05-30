package logger

import (
	"io"
	"log/slog"
	"os"
	"strings"

	"github.com/Innocent9712/much-to-do/Server/MuchToDo/internal/config"
)

// InitLogger initializes the global structured logger based on the application config.
func InitLogger(cfg config.Config) {
	var writers []io.Writer
	writers = append(writers, os.Stdout)

	if strings.EqualFold(cfg.Environment, "production") && cfg.LogFile != "" {
		file, err := os.OpenFile(cfg.LogFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
		if err != nil {
			slog.Error("could not open log file", slog.Any("error", err), slog.String("path", cfg.LogFile))
		} else {
			writers = append(writers, file)
		}
	}

	out := io.MultiWriter(writers...)

	var logHandler slog.Handler

	level := new(slog.LevelVar)
	switch cfg.LogLevel {
	case "DEBUG":
		level.Set(slog.LevelDebug)
	case "WARN":
		level.Set(slog.LevelWarn)
	case "ERROR":
		level.Set(slog.LevelError)
	default:
		level.Set(slog.LevelInfo)
	}

	handlerOpts := &slog.HandlerOptions{
		Level: level,
	}

	if cfg.LogFormat == "json" {
		logHandler = slog.NewJSONHandler(out, handlerOpts)
	} else {
		logHandler = slog.NewTextHandler(out, handlerOpts)
	}

	logger := slog.New(logHandler)
	slog.SetDefault(logger)
}
