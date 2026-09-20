//go:build !windows && !steamworks

package main

import "fmt"

// newSteamTransport: non-Windows builds cannot load steam_api64.dll.
func newSteamTransport(opts steamOpts) (Transport, error) {
	return nil, fmt.Errorf(
		"steam mode requires the Windows steam_bridge.exe (loads steam_api64.dll at runtime). "+
			"AppID=%d peer=%q. Use the prebuilt tools/steam_bridge/steam_bridge.exe on Windows, "+
			"or TCP fallback: -mode tcp. See docs/STEAM.md",
		opts.AppID,
		opts.PeerID,
	)
}
