package main

import (
	"bytes"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/nats-io/nats.go"
)

type todoEvent struct {
	User    string `json:"user"`
	Message string `json:"message"`
	Info    string `json:"info,omitempty"`
}

func main() {
	natsURL := os.Getenv("NATS_URL")
	webhookURL := os.Getenv("GENERIC_WEBHOOK_URL")
	logOnly := os.Getenv("LOG_ONLY") == "true"

	if logOnly {
		log.Printf("broadcaster running in LOG_ONLY mode (no webhook forwarding)")
	} else if webhookURL == "" {
		log.Fatal("GENERIC_WEBHOOK_URL is required unless LOG_ONLY=true")
	}

	nc, err := nats.Connect(natsURL,
		nats.MaxReconnects(-1),
		nats.ReconnectWait(2*time.Second),
	)
	if err != nil {
		log.Fatalf("NATS connect failed: %v", err)
	}
	defer nc.Close()

	log.Printf("connected to NATS at %s; queue group=broadcasters; log_only=%v", natsURL, logOnly)

	// QueueSubscribe is the critical line:
	// every replica uses the SAME queue group name "broadcasters".
	// NATS delivers each message to exactly ONE member of the group.
	_, err = nc.QueueSubscribe("todos", "broadcasters", func(msg *nats.Msg) {
		var evt todoEvent
		if err := json.Unmarshal(msg.Data, &evt); err != nil {
			log.Printf("bad message: %v", err)
			return
		}
		if evt.User == "" {
			evt.User = "bot"
		}

		if logOnly {
			log.Printf("[LOG_ONLY] user=%q message=%q info=%q", evt.User, evt.Message, evt.Info)
			return
		}

		body, _ := json.Marshal(evt)
		req, err := http.NewRequest(http.MethodPost, webhookURL, bytes.NewReader(body))
		if err != nil {
			log.Printf("webhook request build failed: %v", err)
			return
		}
		req.Header.Set("Content-Type", "application/json")

		client := &http.Client{Timeout: 10 * time.Second}
		resp, err := client.Do(req)
		if err != nil {
			log.Printf("webhook POST failed: %v", err)
			return
		}
		defer resp.Body.Close()

		if resp.StatusCode >= 300 {
			log.Printf("webhook returned %s", resp.Status)
			return
		}
		log.Printf("forwarded todo event for user=%q", evt.User)
	})
	if err != nil {
		log.Fatalf("queue subscribe failed: %v", err)
	}

	select {} // block forever
}
