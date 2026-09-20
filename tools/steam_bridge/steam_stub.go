//go:build !steamworks

package main

import "fmt"

type steamOpts struct {
	AppID    uint32
	PeerID   string
	Channel  int
	Inbox    string
	QueueDir string
	PeerFile string
}

// newSteamTransport is used when the binary was built without Steamworks.
// Default builds (`go build` / build.bat) stay dependency-free for TCP/LAN.
// For real Steam P2P, rebuild with build_steamworks.bat (see docs/STEAM.md).
func newSteamTransport(opts steamOpts) (Transport, error) {
	return nil, fmt.Errorf(
		"steam mode requires a Steamworks build (AppID=%d peer=%q). "+
			"Rebuild with tools/steam_bridge/build_steamworks.bat "+
			"(-tags steamworks, CGO, steam_api64.dll). "+
			"Until then use TCP fallback: "+
			"steam_bridge -mode tcp -listen :27073  (host) / "+
			"steam_bridge -mode tcp -dial HOST:27073  (client). "+
			"Details: docs/STEAM.md",
		opts.AppID,
		opts.PeerID,
	)
}
