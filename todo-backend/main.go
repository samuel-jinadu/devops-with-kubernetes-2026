package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"sync"
)

func main() {
	todos := make([]string, 0)
	var mutex sync.Mutex

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(todos)
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
		mutex.Lock()
		defer mutex.Unlock()
		todos = append(todos, todo)
		http.Redirect(w, r, os.Getenv("TODOAPP_ROUTE"), http.StatusSeeOther) 
	})

	port := os.Getenv("PORT")
	fmt.Printf("Server started on port %s\n", port)
	port = ":" + port

	http.ListenAndServe(port, nil)
}
