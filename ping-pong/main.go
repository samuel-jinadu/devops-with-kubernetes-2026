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
	// postgres://user:password@localhost:5432/mydb?sslmode=disable
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
		log.Fatal("Failed to parse config:", err)
	}

	poolConfig.MaxConns = 25
	poolConfig.MinConns = 5
	poolConfig.MaxConnLifetime = time.Hour
	poolConfig.MaxConnIdleTime = 30 * time.Minute
	poolConfig.HealthCheckPeriod = time.Minute

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	pool, err := pgxpool.NewWithConfig(ctx, poolConfig)
	if err != nil {
		log.Fatal("Failed to create pool:", err)
	}
	defer pool.Close()

	// Verify the connection is established
	if err := pool.Ping(ctx); err != nil {
		log.Fatal("Failed to ping database:", err)
	}

	log.Println("Successfully connected to PostgreSQL")

	if err := createTable(ctx, pool); err != nil {
		log.Fatalf("Failed to create table: %v", err)
	}

	port := os.Getenv("PORT")
	fmt.Printf("Server started on port %s\n", port)
	port = ":" + port

	count, err := getCounter(ctx, pool)
	if err != nil {
		log.Fatalf("Something went wrong with getting the count from the database: %v", err)
	}

	var mutex sync.Mutex

	http.HandleFunc("/count", func(w http.ResponseWriter, r *http.Request) {
		mutex.Lock()
		c := count
		mutex.Unlock()
		w.Write([]byte(strconv.Itoa(int(c))))
	})

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		mutex.Lock()
		defer mutex.Unlock()
		fmt.Fprintf(w, "pong %d", count)
		count++
		ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
		defer cancel()
		if err := setCounter(ctx, pool, count); err != nil {
			log.Printf("Something went wrong when trying to set the counter: %v", err)
			return
		}
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
