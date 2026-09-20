//go:build steamworks

package main

import (
	"fmt"
	"log"
)

type steamOpts struct {
	AppID   uint32
	PeerID  string
	Channel int
	Inbox   string
}

type steamTransport struct {
	opts steamOpts
}

// newSteamTransport wires ISteamNetworkingMessages (Steamworks SDK).
// This file is compiled only with -tags steamworks once the SDK is linked via CGO.
// Integration checklist lives in docs/STEAM.md.
func newSteamTransport(opts steamOpts) (Transport, error) {
	if opts.PeerID == "" {
		return nil, fmt.Errorf("steam mode needs -peer SteamID64 or steam_peer.txt")
	}
	// TODO(steamworks): SteamAPI_Init with steam_appid.txt = opts.AppID
	// TODO(steamworks): ISteamNetworkingMessages::SendMessageToUser / ReceiveMessagesOnChannel
	// TODO(steamworks): accept session with peer opts.PeerID on channel opts.Channel
	log.Printf("steamworks build: init pending for peer=%s appid=%d channel=%d", opts.PeerID, opts.AppID, opts.Channel)
	return nil, fmt.Errorf("steamworks CGO bindings not linked yet — see docs/STEAM.md")
}

func (t *steamTransport) Name() string { return "steam" }

func (t *steamTransport) Send(payload []byte) error {
	return fmt.Errorf("steam send not linked")
}

func (t *steamTransport) Close() error { return nil }
