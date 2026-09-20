//go:build steamworks

package main

/*
#cgo windows,amd64 LDFLAGS: -lsteam_api64
#cgo windows,386 LDFLAGS: -lsteam_api
#cgo linux LDFLAGS: -lsteam_api
#cgo darwin LDFLAGS: -lsteam_api

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "steam_abi.h"

static void mapsync_identity_from_steamid64(SteamNetworkingIdentity *id, uint64_t steamID64) {
	memset(id, 0, sizeof(*id));
	id->m_eType = k_ESteamNetworkingIdentityType_SteamID;
	id->m_cbSize = 8;
	id->m_steamID64 = steamID64;
}

static int mapsync_steam_init(void) {
	if (!SteamAPI_IsSteamRunning()) {
		return -1;
	}
	if (!SteamAPI_Init()) {
		return -2;
	}
	SteamAPI_ManualDispatch_Init();
	return 0;
}

static void mapsync_steam_shutdown(void) {
	SteamAPI_Shutdown();
}

static uint64_t mapsync_local_steamid64(void) {
	ISteamUser *user = SteamAPI_SteamUser_SteamAPI_v023();
	if (!user) {
		return 0;
	}
	return SteamAPI_ISteamUser_GetSteamID(user);
}

static ISteamNetworkingMessages *mapsync_netmsgs(void) {
	return SteamAPI_SteamNetworkingMessages_SteamAPI_v002();
}

static int mapsync_send(uint64_t peer, const void *data, uint32_t len, int channel) {
	ISteamNetworkingMessages *msgs = mapsync_netmsgs();
	if (!msgs) {
		return -1;
	}
	SteamNetworkingIdentity id;
	mapsync_identity_from_steamid64(&id, peer);
	int flags = k_nSteamNetworkingSend_Reliable | k_nSteamNetworkingSend_AutoRestartBrokenSession;
	return SteamAPI_ISteamNetworkingMessages_SendMessageToUser(msgs, &id, data, len, flags, channel);
}

static int mapsync_recv(int channel, SteamNetworkingMessage_t **out, int maxn) {
	ISteamNetworkingMessages *msgs = mapsync_netmsgs();
	if (!msgs) {
		return -1;
	}
	return SteamAPI_ISteamNetworkingMessages_ReceiveMessagesOnChannel(msgs, channel, out, maxn);
}

static void mapsync_release_msg(SteamNetworkingMessage_t *msg) {
	if (msg && msg->m_pfnRelease) {
		msg->m_pfnRelease(msg);
	}
}

static int mapsync_accept(uint64_t peer) {
	ISteamNetworkingMessages *msgs = mapsync_netmsgs();
	if (!msgs) {
		return 0;
	}
	SteamNetworkingIdentity id;
	mapsync_identity_from_steamid64(&id, peer);
	return SteamAPI_ISteamNetworkingMessages_AcceptSessionWithUser(msgs, &id) ? 1 : 0;
}

static void mapsync_pump_callbacks(uint64_t *acceptedPeerOut) {
	if (acceptedPeerOut) {
		*acceptedPeerOut = 0;
	}
	HSteamPipe pipe = SteamAPI_GetHSteamPipe();
	SteamAPI_ManualDispatch_RunFrame(pipe);
	CallbackMsg_t msg;
	while (SteamAPI_ManualDispatch_GetNextCallback(pipe, &msg)) {
		if (msg.m_iCallback == k_iSteamNetworkingMessagesCallbacks + 1 &&
			msg.m_cubParam >= (int)sizeof(SteamNetworkingMessagesSessionRequest_t) &&
			msg.m_pubParam != NULL) {
			SteamNetworkingMessagesSessionRequest_t *req =
				(SteamNetworkingMessagesSessionRequest_t *)msg.m_pubParam;
			uint64_t peer = req->m_identityRemote.m_steamID64;
			mapsync_accept(peer);
			if (acceptedPeerOut && *acceptedPeerOut == 0) {
				*acceptedPeerOut = peer;
			}
		}
		SteamAPI_ManualDispatch_FreeLastCallback(pipe);
	}
}

// AppID is encoded in the low 24 bits of CGameID for standard Steam apps.
static uint32_t mapsync_appid_from_gameid(uint64_t gameID) {
	return (uint32_t)(gameID & 0xFFFFFF);
}

static int mapsync_list_friends_playing(uint32_t appID, uint64_t *outIDs, int maxOut, char *names, int nameStride) {
	ISteamFriends *friends = SteamAPI_SteamFriends_SteamAPI_v017();
	if (!friends || !outIDs || maxOut <= 0) {
		return 0;
	}
	int n = SteamAPI_ISteamFriends_GetFriendCount(friends, k_EFriendFlagImmediate);
	int found = 0;
	for (int i = 0; i < n && found < maxOut; i++) {
		uint64_t fid = SteamAPI_ISteamFriends_GetFriendByIndex(friends, i, k_EFriendFlagImmediate);
		FriendGameInfo_t info;
		memset(&info, 0, sizeof(info));
		if (!SteamAPI_ISteamFriends_GetFriendGamePlayed(friends, fid, &info)) {
			continue;
		}
		if (mapsync_appid_from_gameid(info.m_gameID) != appID) {
			continue;
		}
		outIDs[found] = fid;
		if (names && nameStride > 0) {
			const char *pn = SteamAPI_ISteamFriends_GetFriendPersonaName(friends, fid);
			snprintf(names + found * nameStride, (size_t)nameStride, "%s", pn ? pn : "");
		}
		found++;
	}
	return found;
}
*/
import "C"

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
	"unsafe"
)

type steamOpts struct {
	AppID    uint32
	PeerID   string
	Channel  int
	Inbox    string
	QueueDir string
	PeerFile string
}

type steamTransport struct {
	opts   steamOpts
	peer   uint64
	mu     sync.Mutex
	closed chan struct{}
	wg     sync.WaitGroup
}

func newSteamTransport(opts steamOpts) (Transport, error) {
	if opts.Channel < 0 {
		opts.Channel = 1
	}
	if err := writeSteamAppID(opts.AppID); err != nil {
		log.Printf("warn: could not write steam_appid.txt: %v", err)
	}

	rc := int(C.mapsync_steam_init())
	switch rc {
	case 0:
		// ok
	case -1:
		return nil, fmt.Errorf("Steam client is not running — start Steam, log in, then retry (see docs/STEAM.md)")
	default:
		return nil, fmt.Errorf("SteamAPI_Init failed (is steam_api64.dll next to steam_bridge.exe? steam_appid.txt=%d?). See docs/STEAM.md", opts.AppID)
	}

	selfID := uint64(C.mapsync_local_steamid64())
	if selfID == 0 {
		C.mapsync_steam_shutdown()
		return nil, fmt.Errorf("SteamAPI returned local SteamID 0 — ensure you are logged into Steam")
	}
	log.Printf("steam local SteamID64=%d", selfID)
	if opts.QueueDir != "" {
		selfPath := filepath.Join(opts.QueueDir, "steam_self.txt")
		if err := os.WriteFile(selfPath, []byte(strconv.FormatUint(selfID, 10)+"\n"), 0o644); err != nil {
			log.Printf("warn: write steam_self.txt: %v", err)
		} else {
			log.Printf("wrote %s (share this with your co-op partner)", selfPath)
		}
	}

	peer, err := resolveSteamPeer(opts, selfID)
	if err != nil {
		C.mapsync_steam_shutdown()
		return nil, err
	}

	t := &steamTransport{
		opts:   opts,
		peer:   peer,
		closed: make(chan struct{}),
	}
	if peer != 0 {
		log.Printf("steam peer SteamID64=%d channel=%d", peer, opts.Channel)
		C.mapsync_accept(C.uint64_t(peer))
		if opts.PeerFile != "" {
			_ = os.WriteFile(opts.PeerFile, []byte(strconv.FormatUint(peer, 10)+"\n"), 0o644)
		}
	} else {
		log.Printf("steam peer not set yet — waiting for session request or steam_peer.txt / -peer")
	}

	t.wg.Add(1)
	go t.recvLoop()
	return t, nil
}

func writeSteamAppID(appID uint32) error {
	// Steam looks for steam_appid.txt next to the executable (and often CWD).
	exe, err := os.Executable()
	candidates := []string{"steam_appid.txt"}
	if err == nil {
		candidates = append([]string{filepath.Join(filepath.Dir(exe), "steam_appid.txt")}, candidates...)
	}
	body := []byte(strconv.FormatUint(uint64(appID), 10) + "\n")
	var last error
	written := false
	for _, p := range candidates {
		if err := os.WriteFile(p, body, 0o644); err != nil {
			last = err
			continue
		}
		written = true
		log.Printf("steam_appid.txt=%s (%d)", p, appID)
	}
	if !written {
		return last
	}
	return nil
}

func resolveSteamPeer(opts steamOpts, selfID uint64) (uint64, error) {
	if p := parseSteamID64(opts.PeerID); p != 0 {
		if p == selfID {
			return 0, fmt.Errorf("peer SteamID64 equals local id (%d)", selfID)
		}
		return p, nil
	}

	// Auto-discover: friends currently playing Remnant II (same AppID).
	var ids [16]C.uint64_t
	nameBuf := make([]byte, 16*64)
	n := int(C.mapsync_list_friends_playing(
		C.uint32_t(opts.AppID),
		&ids[0],
		16,
		(*C.char)(unsafe.Pointer(&nameBuf[0])),
		64,
	))
	candidates := make([]uint64, 0, n)
	for i := 0; i < n; i++ {
		id := uint64(ids[i])
		if id == 0 || id == selfID {
			continue
		}
		name := cStringAt(nameBuf, i, 64)
		log.Printf("steam friend playing app %d: %s (%d)", opts.AppID, name, id)
		candidates = append(candidates, id)
	}
	switch len(candidates) {
	case 0:
		// Allowed: peer may connect inbound, or user writes steam_peer.txt later.
		return 0, nil
	case 1:
		log.Printf("auto-selected sole friend playing Remnant II as peer")
		return candidates[0], nil
	default:
		log.Printf("multiple friends playing — pass -peer SteamID64 or write one id to steam_peer.txt")
		return 0, nil
	}
}

func cStringAt(buf []byte, index, stride int) string {
	start := index * stride
	if start < 0 || start >= len(buf) {
		return ""
	}
	end := start + stride
	if end > len(buf) {
		end = len(buf)
	}
	chunk := buf[start:end]
	if i := strings.IndexByte(string(chunk), 0); i >= 0 {
		return string(chunk[:i])
	}
	return strings.TrimRight(string(chunk), "\x00")
}

func parseSteamID64(s string) uint64 {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0
	}
	v, err := strconv.ParseUint(s, 10, 64)
	if err != nil {
		return 0
	}
	return v
}

func (t *steamTransport) Name() string { return "steam" }

func (t *steamTransport) Send(payload []byte) error {
	t.mu.Lock()
	peer := t.peer
	t.mu.Unlock()
	if peer == 0 {
		// Re-read peer file in case the partner shared their id mid-session.
		if t.opts.PeerFile != "" {
			if b, err := os.ReadFile(t.opts.PeerFile); err == nil {
				if p := parseSteamID64(string(b)); p != 0 {
					t.mu.Lock()
					t.peer = p
					peer = p
					t.mu.Unlock()
					log.Printf("steam peer loaded from file: %d", p)
					C.mapsync_accept(C.uint64_t(p))
				}
			}
		}
	}
	if peer == 0 {
		return fmt.Errorf("no steam peer yet (set -peer, steam_peer.txt, or wait for inbound session)")
	}
	if len(payload) == 0 {
		return nil
	}
	rc := int(C.mapsync_send(
		C.uint64_t(peer),
		unsafe.Pointer(&payload[0]),
		C.uint32_t(len(payload)),
		C.int(t.opts.Channel),
	))
	if rc != C.k_EResultOK {
		return fmt.Errorf("SendMessageToUser failed EResult=%d", rc)
	}
	return nil
}

func (t *steamTransport) recvLoop() {
	defer t.wg.Done()
	msgs := make([]*C.SteamNetworkingMessage_t, 32)
	ticker := time.NewTicker(15 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-t.closed:
			return
		case <-ticker.C:
		}

		var accepted C.uint64_t
		C.mapsync_pump_callbacks(&accepted)
		if accepted != 0 {
			t.mu.Lock()
			if t.peer == 0 {
				t.peer = uint64(accepted)
				log.Printf("steam accepted inbound session peer=%d", t.peer)
				if t.opts.PeerFile != "" {
					_ = os.WriteFile(t.opts.PeerFile, []byte(strconv.FormatUint(t.peer, 10)+"\n"), 0o644)
				}
			}
			t.mu.Unlock()
		}

		n := int(C.mapsync_recv(
			C.int(t.opts.Channel),
			(**C.SteamNetworkingMessage_t)(unsafe.Pointer(&msgs[0])),
			C.int(len(msgs)),
		))
		if n <= 0 {
			continue
		}
		for i := 0; i < n; i++ {
			msg := msgs[i]
			if msg == nil {
				continue
			}
			size := int(msg.m_cbSize)
			if size > 0 && msg.m_pData != nil {
				payload := C.GoBytes(msg.m_pData, C.int(size))
				writeInbox(t.opts.Inbox, payload)
				peer := uint64(msg.m_identityPeer.m_steamID64)
				if peer != 0 {
					t.mu.Lock()
					if t.peer == 0 {
						t.peer = peer
						log.Printf("steam learned peer from message: %d", peer)
					}
					t.mu.Unlock()
				}
			}
			C.mapsync_release_msg(msg)
			msgs[i] = nil
		}
	}
}

func (t *steamTransport) Close() error {
	select {
	case <-t.closed:
	default:
		close(t.closed)
	}
	t.wg.Wait()
	C.mapsync_steam_shutdown()
	return nil
}
