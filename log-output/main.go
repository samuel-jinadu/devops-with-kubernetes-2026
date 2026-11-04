package main

import (
	"context"
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
	Greeting    string `json:"greeting"` // <-- Added
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

		bodyString := strings.TrimSpace(string(bodyBytes))
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

		greeterURL := os.Getenv("GREETER_URL")
		greeting := "greeter unavailable"
		if greeterURL != "" {
			gResp, gErr := http.Get(greeterURL)
			if gErr == nil {
				gBodyBytes, _ := io.ReadAll(gResp.Body)
				greeting = strings.TrimSpace(string(gBodyBytes))
				gResp.Body.Close()
			}
		}

		channel <- JSONResponse{
			Timestamp:   timestamp,
			CurrentUUID: payload.String(),
			Pingpong:    pingpongVal,
			FileContent: string(fileContent),
			MESSAGE:     os.Getenv("MESSAGE"),
			Greeting:    greeting,
		}

		output := fmt.Sprintf("%s: %s\nPing / Pong: %d\nfile content: %sMESSAGE: %s\ngreetings: %s\n",
			timestamp, payload.String(), pingpongVal, string(fileContent), os.Getenv("MESSAGE"), greeting)
		fmt.Print(output)
		time.Sleep(5 * time.Second)
		drainChannel(channel)
	}
}

func drainChannel(ch chan JSONResponse) {
	for {
		select {
		case <-ch:
		default:
			return
		}
	}
}

func server(channel chan JSONResponse) {
	port := os.Getenv("PORT")
	fmt.Printf("Server started on port %s\n", port)
	port = ":" + port

	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	http.HandleFunc("/readyz", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()

		req, err := http.NewRequestWithContext(ctx, http.MethodGet, os.Getenv("PINGPONGURL"), nil)
		if err != nil {
			http.Error(w, "bad config", http.StatusServiceUnavailable)
			return
		}
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			http.Error(w, "pingpong unreachable: "+err.Error(), http.StatusServiceUnavailable)
			return
		}
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			http.Error(w, "pingpong returned "+resp.Status, http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	http.HandleFunc("/log", func(w http.ResponseWriter, r *http.Request) {
		data := <-channel
		json.NewEncoder(w).Encode(data)
	})
	http.ListenAndServe(port, nil)
}
