//go:build !steamworks

package main

import "fmt"

type steamOpts struct {
	AppID   uint32
	PeerID  string
	Channel int
	Inbox   string
}

// newSteamTransport is a stub until the binary is built with Steamworks SDK.
// Build with: go build -tags steamworks
// and provide steam_api headers/libs (see docs/STEAM.md).
func newSteamTransport(opts steamOpts) (Transport, error) {
	return nil, fmt.Errorf(
		"steam mode requires a steamworks-tagged build (AppID=%d peer=%q). "+
			"For WAN testing without Steamworks SDK, use: "+
			"steam_bridge -mode tcp -listen :27073  (host) and "+
			"steam_bridge -mode tcp -dial HOST:27073  (client). "+
			"See docs/STEAM.md",
		opts.AppID,
		opts.PeerID,
	)
}
