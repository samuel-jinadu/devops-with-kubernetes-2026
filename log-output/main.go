package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"time"
	"uuid"
)

type JSONResponse struct {
	Timestamp   string `json:"timestamp"`
	CurrentUUID string `json:"current_uuid"`
}

func main() {
	channel := make(chan JSONResponse, 1)
	go log(channel)
	server(channel)
}

func log(channel chan JSONResponse) {
	payload := uuid.New()
	for {
		timestamp := time.Now().UTC().String()
		output := fmt.Sprintf("%s: %s\n", timestamp, payload.String())
		fmt.Print(output)
		channel <- JSONResponse{
			Timestamp:   timestamp,
			CurrentUUID: payload.String(),
		}
		time.Sleep(5 * time.Second)
		drainChannel(channel)
	}
}

func drainChannel(ch chan JSONResponse) {
	for {
		select {
		case <-ch:
			// Item received and discarded
		default:
			// Channel is empty, break the loop
			return
		}
	}
}

func server(channel chan JSONResponse) {
	port := os.Getenv("PORT")
	fmt.Printf("Server started on port %s\n", port)
	port = ":" + port

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		data := <-channel
		json.NewEncoder(w).Encode(data)
	})
	http.ListenAndServe(port, nil)
}
