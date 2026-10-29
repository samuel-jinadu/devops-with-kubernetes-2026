package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
	"uuid"
)

type JSONResponse struct {
	Timestamp   string `json:"timestamp"`
	CurrentUUID string `json:"current_uuid"`
	Pingpong    int    `json:"Ping / Pongs"`
	MESSAGE     string `json:"MESSAGE"`
	FileContent string `json:"file content"`
}

func main() {
	channel := make(chan JSONResponse, 1)
	go log_loop(channel)
	server(channel)
}

func log_loop(channel chan JSONResponse) {
	payload := uuid.New()
	for {
		timestamp := time.Now().UTC().String()

		pingpongurl := os.Getenv("PINGPONGURL")
		resp, err := http.Get(pingpongurl)
		if err != nil {
			fmt.Printf("An error ocurred when trying to get count from ping pong: %v\n", err)
			time.Sleep(5 * time.Second)
			continue
		}
		bodyBytes, err := io.ReadAll(resp.Body)
		if err != nil {
			fmt.Println("Error reading response body:", err)
			return
		}

		// Clean up whitespace/newlines from the response string
		bodyString := strings.TrimSpace(string(bodyBytes))

		// Convert string to integer
		pingpongVal, err := strconv.Atoi(bodyString)
		if err != nil {
			fmt.Println("Error converting string to int:", err)
			return
		}
		resp.Body.Close()
		fileContent, err := os.ReadFile("/config/information.txt")
		if err != nil {
			fmt.Printf("could not read /config/information.txt: %v\n", err)
		}
		channel <- JSONResponse{
			Timestamp:   timestamp,
			CurrentUUID: payload.String(),
			Pingpong:    pingpongVal,
			FileContent: string(fileContent),
			MESSAGE:     os.Getenv("MESSAGE"),
		}
		output := fmt.Sprintf("%s: %s\nPing / Pong: %d\nfile content: %sMESSAGE: %s", timestamp, payload.String(), pingpongVal, string(fileContent), os.Getenv("MESSAGE"))
		fmt.Print(output)
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

	// Health‑check endpoint for GKE Ingress
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	http.HandleFunc("/log", func(w http.ResponseWriter, r *http.Request) {
		data := <-channel
		json.NewEncoder(w).Encode(data)
	})
	http.ListenAndServe(port, nil)
}
