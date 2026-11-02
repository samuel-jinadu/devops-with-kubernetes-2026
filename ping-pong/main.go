package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	server()
}

func server() {
	dsn := fmt.Sprintf(
		"postgres://%s:%s@%s:%s/%s?sslmode=disable",
		os.Getenv("POSTGRES_USER"),
		os.Getenv("POSTGRES_PASSWORD"),
		os.Getenv("POSTGRES_HOST"),
		os.Getenv("POSTGRES_PORT"),
		os.Getenv("POSTGRES_DB"),
	)

	poolConfig, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		log.Fatal("Failed to parse config:", err) // this IS a config error, still fatal
	}
	poolConfig.MaxConns = 25
	poolConfig.MinConns = 5
	poolConfig.MaxConnLifetime = time.Hour
	poolConfig.MaxConnIdleTime = 30 * time.Minute
	poolConfig.HealthCheckPeriod = time.Minute

	// Lazy: does not connect, does not fail if DB is down.
	pool, err := pgxpool.NewWithConfig(context.Background(), poolConfig)
	if err != nil {
		log.Fatal("Failed to create pool:", err)
	}
	defer pool.Close()

	var mutex sync.Mutex
	var count int64

	// Background: retry table creation + counter load until both succeed.
	// Non-blocking. The pod serves 503 on /readyz until this finishes.
	go func() {
		for {
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			if err := pool.Ping(ctx); err == nil {
				if err := createTable(ctx, pool); err == nil {
					if c, err := getCounter(ctx, pool); err == nil {
						mutex.Lock()
						count = c
						mutex.Unlock()
						log.Printf("Initialized counter = %d", c)
						cancel()
						return
					}
				}
			}
			cancel()
			time.Sleep(3 * time.Second)
		}
	}()

	port := os.Getenv("PORT")
	fmt.Printf("Server started on port %s\n", port)
	port = ":" + port

	// Liveness: process is up. Does NOT touch the DB.
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	// Readiness: DB must be reachable.
	http.HandleFunc("/readyz", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if err := pool.Ping(ctx); err != nil {
			http.Error(w, "db unavailable", http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	http.HandleFunc("/count", func(w http.ResponseWriter, r *http.Request) {
		mutex.Lock()
		c := count
		mutex.Unlock()
		w.Write([]byte(strconv.Itoa(int(c))))
	})

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		mutex.Lock()
		defer mutex.Unlock()
		ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
		defer cancel()
		next := count + 1
		if err := setCounter(ctx, pool, next); err != nil {
			http.Error(w, "db unavailable", http.StatusServiceUnavailable)
			return
		}
		count = next
		fmt.Fprintf(w, "pong %d", count)
	})

	log.Fatal(http.ListenAndServe(port, nil))
}

func createTable(ctx context.Context, pool *pgxpool.Pool) error {
	_, err := pool.Exec(ctx, `
        CREATE TABLE IF NOT EXISTS counters (
			id          INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
			count       BIGINT NOT NULL DEFAULT 0,
			updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
		);
		INSERT INTO counters (id) VALUES (1) ON CONFLICT DO NOTHING;
    `)
	return err
}

func setCounter(ctx context.Context, pool *pgxpool.Pool, newValue int64) error {
	tag, err := pool.Exec(ctx,
		`UPDATE counters SET count = $1, updated_at = now() WHERE id = 1`,
		newValue,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("counter not found")
	}
	return nil
}

func getCounter(ctx context.Context, pool *pgxpool.Pool) (int64, error) {
	var value int64
	if err := pool.QueryRow(ctx, "SELECT count FROM counters WHERE id = 1").Scan(&value); err != nil {
		return 0, err // caller can check errors.Is(err, pgx.ErrNoRows)
	}
	return value, nil
}
