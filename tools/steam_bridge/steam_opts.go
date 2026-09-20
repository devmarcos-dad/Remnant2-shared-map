package main

// Shared options for all Steam transport builds (dyn / CGO / stub).
type steamOpts struct {
	AppID    uint32
	PeerID   string
	Channel  int
	Inbox    string
	QueueDir string
	PeerFile string
}
