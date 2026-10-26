package main

import (
	"encoding/json"
	"fmt"
	"log"
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

	jsonPath := os.Getenv("FILEPATH")
	which := os.Getenv("WHICH")
	switch which {
	case "Generator":
		log_data(jsonPath)
	case "Reader":
		server(jsonPath)
	default:
		log.Fatalf("WHICH environmenatal variabl passed only accepts Generator or Reader")
	}

}

func log_data(path string) {
	payload := uuid.New()
	for {
		timestamp := time.Now().UTC().String()
		// output := fmt.Sprintf("%s: %s\n", timestamp, payload.String())
		// fmt.Print(output)
		data := JSONResponse{
			Timestamp:   timestamp,
			CurrentUUID: payload.String(),
		}

		jsonifiedData, err := json.MarshalIndent(data, "", "    ")
		if err != nil {
			log.Print("JSON Marshalling failed!\n")
			time.Sleep(5 * time.Second)
			continue
		}

		log.Printf("Writing to path: %s\n", path)
		err = os.WriteFile(path, jsonifiedData, 0644)

		if err != nil {
			log.Printf("Error writing file: %v", err)
			time.Sleep(5 * time.Second)
			continue
		}

		time.Sleep(5 * time.Second)
		// drainChannel(channel)
	}
}

func server(path string) {
	port := os.Getenv("PORT")
	fmt.Printf("Server started on port %s\n", port)
	port = ":" + port

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		data, err := os.ReadFile(path)
		if err != nil {
			http.Error(w, "File not found", http.StatusNotFound)
			return
		}

		w.Header().Add("Content-Type", "application/json")
		w.Write(data)
	})
	http.ListenAndServe(port, nil)
}
