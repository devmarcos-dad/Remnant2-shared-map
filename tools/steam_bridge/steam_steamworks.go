//go:build steamworks

package main

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

// AppID low 24 bits of CGameID.
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

type steamTransportCGO struct {
	opts   steamOpts
	peer   uint64
	mu     sync.Mutex
	closed chan struct{}
	wg     sync.WaitGroup
}

// Optional CGO-linked build. Default Windows binary uses runtime DLL load instead.
func newSteamTransport(opts steamOpts) (Transport, error) {
	if opts.Channel < 0 {
		opts.Channel = 1
	}
	body := []byte(strconv.FormatUint(uint64(opts.AppID), 10) + "\n")
	_ = os.WriteFile("steam_appid.txt", body, 0o644)
	if exe, err := os.Executable(); err == nil {
		_ = os.WriteFile(filepath.Join(filepath.Dir(exe), "steam_appid.txt"), body, 0o644)
	}

	rc := int(C.mapsync_steam_init())
	if rc == -1 {
		return nil, fmt.Errorf("Steam client is not running")
	}
	if rc != 0 {
		return nil, fmt.Errorf("SteamAPI_Init failed")
	}

	selfID := uint64(C.mapsync_local_steamid64())
	if selfID == 0 {
		C.mapsync_steam_shutdown()
		return nil, fmt.Errorf("local SteamID 0")
	}
	if opts.QueueDir != "" {
		_ = os.WriteFile(filepath.Join(opts.QueueDir, "steam_self.txt"), []byte(strconv.FormatUint(selfID, 10)+"\n"), 0o644)
	}

	peer := parseSteamID64CGO(opts.PeerID)
	if peer == 0 {
		var ids [16]C.uint64_t
		n := int(C.mapsync_list_friends_playing(C.uint32_t(opts.AppID), &ids[0], 16, nil, 0))
		var cands []uint64
		for i := 0; i < n; i++ {
			id := uint64(ids[i])
			if id != 0 && id != selfID {
				cands = append(cands, id)
			}
		}
		if len(cands) == 1 {
			peer = cands[0]
		}
	}

	t := &steamTransportCGO{opts: opts, peer: peer, closed: make(chan struct{})}
	if peer != 0 {
		C.mapsync_accept(C.uint64_t(peer))
		log.Printf("steam peer=%d", peer)
	}
	t.wg.Add(1)
	go t.recvLoop()
	return t, nil
}

func parseSteamID64CGO(s string) uint64 {
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

func (t *steamTransportCGO) Name() string { return "steam" }

func (t *steamTransportCGO) Send(payload []byte) error {
	t.mu.Lock()
	peer := t.peer
	t.mu.Unlock()
	if peer == 0 {
		return fmt.Errorf("no steam peer yet")
	}
	if len(payload) == 0 {
		return nil
	}
	rc := int(C.mapsync_send(C.uint64_t(peer), unsafe.Pointer(&payload[0]), C.uint32_t(len(payload)), C.int(t.opts.Channel)))
	if rc != C.k_EResultOK {
		return fmt.Errorf("SendMessageToUser EResult=%d", rc)
	}
	return nil
}

func (t *steamTransportCGO) recvLoop() {
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
			}
			t.mu.Unlock()
		}
		n := int(C.mapsync_recv(C.int(t.opts.Channel), (**C.SteamNetworkingMessage_t)(unsafe.Pointer(&msgs[0])), C.int(len(msgs))))
		for i := 0; i < n; i++ {
			msg := msgs[i]
			if msg == nil {
				continue
			}
			size := int(msg.m_cbSize)
			if size > 0 && msg.m_pData != nil {
				writeInbox(t.opts.Inbox, C.GoBytes(msg.m_pData, C.int(size)))
			}
			C.mapsync_release_msg(msg)
			msgs[i] = nil
		}
	}
}

func (t *steamTransportCGO) Close() error {
	select {
	case <-t.closed:
	default:
		close(t.closed)
	}
	t.wg.Wait()
	C.mapsync_steam_shutdown()
	return nil
}
