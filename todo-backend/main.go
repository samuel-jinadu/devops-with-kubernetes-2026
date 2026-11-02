package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"sync/atomic"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Todo struct {
	ID   int    `db:"id"      json:"id"`
	Text string `db:"todo"    json:"text"`
	Done bool   `db:"is_done" json:"done"`
}

func main() {
	pool := setupPostgres()
	defer pool.Close()
	var isHealthy atomic.Bool
	isHealthy.Store(true)

	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		if !isHealthy.Load() {
			http.Error(w, "unhealthy", http.StatusServiceUnavailable)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if err := pool.Ping(ctx); err != nil {
			http.Error(w, "db unavailable", http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	http.HandleFunc("/break-app", func(w http.ResponseWriter, r *http.Request) {
		isHealthy.Store(false)
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("broken"))
	})

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if !isHealthy.Load() {
			http.Error(w, "internal server error", http.StatusInternalServerError)
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
		defer cancel()
		todos, err := getTodos(ctx, pool)
		if err != nil {
			log.Printf("Something went wrong getting the todos: %v", err)
			http.Error(w, "internal server error", http.StatusInternalServerError)
			return
		}
		json.NewEncoder(w).Encode(todos)
	})

	http.HandleFunc("PUT /todos/{id}", func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id")
		ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
		defer cancel()

		if err := markTodoDone(ctx, pool, id); err != nil {
			http.Error(w, fmt.Sprintf("An issue occurd when trying to mark todo done: %s", id), http.StatusBadRequest)
			return
		}
		http.Redirect(w, r, os.Getenv("TODOAPP_ROUTE"), http.StatusSeeOther)
	})

	http.HandleFunc("/submit", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		if err := r.ParseForm(); err != nil {
			http.Error(w, "bad form", http.StatusBadRequest)
			return
		}

		todo := r.PostFormValue("todo")
		log.Printf("Backend received POST request for todo with value: %s\n", todo)
		if len(todo) > 140 {
			log.Printf("REJECTED todo too long (len=%d): %q", len(todo), todo)
			http.Error(w, "todo must be ≤140 characters", http.StatusBadRequest)
			return
		}
		if todo == "" {
			http.Error(w, "todo must not be empty", http.StatusBadRequest)
			return
		}
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := addTodo(ctx, pool, todo); err != nil {
			http.Error(w, "An issue occured inserting the new todo into the databse", http.StatusInternalServerError)
			return
		}
		http.Redirect(w, r, os.Getenv("TODOAPP_ROUTE"), http.StatusSeeOther)
	})

	port := os.Getenv("PORT")
	fmt.Printf("Server started on port %s\n", port)
	port = ":" + port

	log.Fatal(http.ListenAndServe(port, nil))
}

func setupPostgres() *pgxpool.Pool {
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

	// Verify the connection is established
	if err := pool.Ping(ctx); err != nil {
		log.Fatal("Failed to ping database:", err)
	}

	log.Println("Successfully connected to PostgreSQL")

	if err := createTable(ctx, pool); err != nil {
		log.Fatalf("Failed to create table: %v", err)
	}

	return pool
}

func createTable(ctx context.Context, pool *pgxpool.Pool) error {
	_, err := pool.Exec(ctx, `
        CREATE TABLE IF NOT EXISTS Todos (
			id          INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
			todo       TEXT NOT NULL,
			is_done		BOOLEAN DEFAULT FALSE,
			created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
		);
    `)
	return err
}

func getTodos(ctx context.Context, pool *pgxpool.Pool) ([]Todo, error) {
	rows, err := pool.Query(ctx, "SELECT id, todo, is_done FROM Todos")
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowToStructByPos[Todo])
}

func addTodo(ctx context.Context, pool *pgxpool.Pool, todo string) error {
	_, err := pool.Exec(ctx, `INSERT INTO Todos (todo) VALUES ($1)`, todo)
	return err
}

func markTodoDone(ctx context.Context, pool *pgxpool.Pool, id string) error {
	_, err := pool.Exec(ctx, `UPDATE Todos SET is_done = TRUE WHERE id = $1`, id)
	return err
}
