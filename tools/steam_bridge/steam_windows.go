//go:build windows && !steamworks

package main

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

// Runtime Steamworks via steam_api64.dll (no CGO / no SDK at build time).
// Remnant II already ships steam_api64.dll under Binaries\Win64 — we load that.

const (
	kIdentitySteamID     = 16
	kSendReliable        = 8
	kSendAutoRestart     = 512
	kFriendFlagImmediate = 0x04
	kNetMsgCallbacks     = 1250
	kEResultOK           = 1
	identityBytes        = 136 // SteamNetworkingIdentity on Win64
)

type steamAPI struct {
	dll *windows.DLL

	init            *windows.Proc
	shutdown        *windows.Proc
	isRunning       *windows.Proc
	getPipe         *windows.Proc
	manualInit      *windows.Proc
	manualRun       *windows.Proc
	manualNext      *windows.Proc
	manualFree      *windows.Proc
	steamUser       *windows.Proc
	getSteamID      *windows.Proc
	steamFriends    *windows.Proc
	friendCount     *windows.Proc
	friendByIndex   *windows.Proc
	friendName      *windows.Proc
	friendGame      *windows.Proc
	netMessages     *windows.Proc
	sendToUser      *windows.Proc
	recvOnChannel   *windows.Proc
	acceptSession   *windows.Proc
	releaseMessage  *windows.Proc
}

type steamTransport struct {
	opts   steamOpts
	api    *steamAPI
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
		log.Printf("warn: steam_appid.txt: %v", err)
	}

	api, err := loadSteamAPI()
	if err != nil {
		return nil, err
	}

	if r, _, _ := api.isRunning.Call(); r == 0 {
		api.dll.Release()
		return nil, fmt.Errorf("Steam não está rodando — abra o Steam, faça login e tente de novo")
	}
	if r, _, _ := api.init.Call(); r == 0 {
		api.dll.Release()
		return nil, fmt.Errorf("SteamAPI_Init falhou (AppID %d). Confirme steam_appid.txt e que o Steam está logado. Veja docs/STEAM.md", opts.AppID)
	}
	api.manualInit.Call()

	selfID := api.localSteamID()
	if selfID == 0 {
		api.shutdown.Call()
		api.dll.Release()
		return nil, fmt.Errorf("SteamID local = 0 — faça login no Steam")
	}
	log.Printf("steam local SteamID64=%d", selfID)
	if opts.QueueDir != "" {
		p := filepath.Join(opts.QueueDir, "steam_self.txt")
		_ = os.WriteFile(p, []byte(strconv.FormatUint(selfID, 10)+"\n"), 0o644)
		log.Printf("wrote %s (envie ao parceiro se o auto-peer falhar)", p)
	}

	peer := parseSteamID64(opts.PeerID)
	if peer == 0 {
		peer = api.autoPeer(opts.AppID, selfID)
	}
	if peer == selfID {
		api.shutdown.Call()
		api.dll.Release()
		return nil, fmt.Errorf("peer SteamID64 igual ao local (%d)", selfID)
	}

	t := &steamTransport{
		opts:   opts,
		api:    api,
		peer:   peer,
		closed: make(chan struct{}),
	}
	if peer != 0 {
		log.Printf("steam peer SteamID64=%d channel=%d", peer, opts.Channel)
		api.accept(peer)
		if opts.PeerFile != "" {
			_ = os.WriteFile(opts.PeerFile, []byte(strconv.FormatUint(peer, 10)+"\n"), 0o644)
		}
	} else {
		log.Printf("steam peer ainda vazio — aguardando sessão inbound ou steam_peer.txt")
	}

	t.wg.Add(1)
	go t.recvLoop()
	return t, nil
}

func writeSteamAppID(appID uint32) error {
	body := []byte(strconv.FormatUint(uint64(appID), 10) + "\n")
	var last error
	ok := false
	candidates := []string{"steam_appid.txt"}
	if exe, err := os.Executable(); err == nil {
		candidates = append([]string{filepath.Join(filepath.Dir(exe), "steam_appid.txt")}, candidates...)
	}
	if cwd, err := os.Getwd(); err == nil {
		candidates = append(candidates, filepath.Join(cwd, "steam_appid.txt"))
	}
	seen := map[string]struct{}{}
	for _, p := range candidates {
		if _, dup := seen[p]; dup {
			continue
		}
		seen[p] = struct{}{}
		if err := os.WriteFile(p, body, 0o644); err != nil {
			last = err
			continue
		}
		ok = true
		log.Printf("steam_appid.txt=%s (%d)", p, appID)
	}
	if !ok {
		return last
	}
	return nil
}

func loadSteamAPI() (*steamAPI, error) {
	candidates := steamDLLCandidates()
	var last error
	for _, path := range candidates {
		dll, err := windows.LoadDLL(path)
		if err != nil {
			last = err
			continue
		}
		api := &steamAPI{dll: dll}
		if err := api.bind(); err != nil {
			dll.Release()
			last = err
			continue
		}
		log.Printf("loaded Steam API: %s", path)
		return api, nil
	}
	return nil, fmt.Errorf(
		"não achei steam_api64.dll (tentou: %s). "+
			"Ela já vem com o Remnant em Binaries\\Win64 — rode o bridge a partir do jogo "+
			"ou copie steam_api64.dll para Mods\\MapSync\\Bin\\. Erro: %v",
		strings.Join(candidates, ", "),
		last,
	)
}

func steamDLLCandidates() []string {
	var out []string
	add := func(p string) {
		if p == "" {
			return
		}
		out = append(out, p)
	}
	add("steam_api64.dll")
	if exe, err := os.Executable(); err == nil {
		dir := filepath.Dir(exe)
		add(filepath.Join(dir, "steam_api64.dll"))
		// Mods/MapSync/Bin -> ../../ (Win64)
		add(filepath.Join(dir, "..", "..", "steam_api64.dll"))
		add(filepath.Clean(filepath.Join(dir, "..", "..", "steam_api64.dll")))
	}
	if cwd, err := os.Getwd(); err == nil {
		add(filepath.Join(cwd, "steam_api64.dll"))
	}
	if v := os.Getenv("STEAM_API_DLL"); v != "" {
		add(v)
	}
	// Dedup preserve order
	seen := map[string]struct{}{}
	uniq := make([]string, 0, len(out))
	for _, p := range out {
		key := strings.ToLower(filepath.Clean(p))
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		uniq = append(uniq, p)
	}
	return uniq
}

func (a *steamAPI) bind() error {
	must := func(name string) (*windows.Proc, error) {
		p, err := a.dll.FindProc(name)
		if err != nil {
			return nil, fmt.Errorf("symbol %s: %w", name, err)
		}
		return p, nil
	}
	var err error
	if a.init, err = must("SteamAPI_Init"); err != nil {
		return err
	}
	if a.shutdown, err = must("SteamAPI_Shutdown"); err != nil {
		return err
	}
	if a.isRunning, err = must("SteamAPI_IsSteamRunning"); err != nil {
		return err
	}
	if a.getPipe, err = must("SteamAPI_GetHSteamPipe"); err != nil {
		return err
	}
	if a.manualInit, err = must("SteamAPI_ManualDispatch_Init"); err != nil {
		return err
	}
	if a.manualRun, err = must("SteamAPI_ManualDispatch_RunFrame"); err != nil {
		return err
	}
	if a.manualNext, err = must("SteamAPI_ManualDispatch_GetNextCallback"); err != nil {
		return err
	}
	if a.manualFree, err = must("SteamAPI_ManualDispatch_FreeLastCallback"); err != nil {
		return err
	}

	// Interface accessors — try a few SDK versions.
	a.steamUser = a.findProc(
		"SteamAPI_SteamUser_SteamAPI_v023",
		"SteamAPI_SteamUser_v023",
		"SteamAPI_SteamUser_SteamAPI_v021",
		"SteamAPI_SteamUser_v021",
	)
	if a.steamUser == nil {
		return fmt.Errorf("SteamAPI_SteamUser_* não encontrado na DLL")
	}
	if a.getSteamID, err = must("SteamAPI_ISteamUser_GetSteamID"); err != nil {
		return err
	}

	a.steamFriends = a.findProc(
		"SteamAPI_SteamFriends_SteamAPI_v017",
		"SteamAPI_SteamFriends_v017",
		"SteamAPI_SteamFriends_SteamAPI_v015",
		"SteamAPI_SteamFriends_v015",
	)
	if a.steamFriends == nil {
		return fmt.Errorf("SteamAPI_SteamFriends_* não encontrado na DLL")
	}
	if a.friendCount, err = must("SteamAPI_ISteamFriends_GetFriendCount"); err != nil {
		return err
	}
	if a.friendByIndex, err = must("SteamAPI_ISteamFriends_GetFriendByIndex"); err != nil {
		return err
	}
	if a.friendName, err = must("SteamAPI_ISteamFriends_GetFriendPersonaName"); err != nil {
		return err
	}
	if a.friendGame, err = must("SteamAPI_ISteamFriends_GetFriendGamePlayed"); err != nil {
		return err
	}

	a.netMessages = a.findProc(
		"SteamAPI_SteamNetworkingMessages_SteamAPI_v002",
		"SteamAPI_SteamNetworkingMessages_v002",
	)
	if a.netMessages == nil {
		return fmt.Errorf("SteamAPI_SteamNetworkingMessages_* não encontrado na DLL")
	}
	if a.sendToUser, err = must("SteamAPI_ISteamNetworkingMessages_SendMessageToUser"); err != nil {
		return err
	}
	if a.recvOnChannel, err = must("SteamAPI_ISteamNetworkingMessages_ReceiveMessagesOnChannel"); err != nil {
		return err
	}
	if a.acceptSession, err = must("SteamAPI_ISteamNetworkingMessages_AcceptSessionWithUser"); err != nil {
		return err
	}
	// Optional — fall back to m_pfnRelease on the message struct.
	a.releaseMessage, _ = a.dll.FindProc("SteamAPI_SteamNetworkingMessage_t_Release")
	return nil
}

func (a *steamAPI) findProc(names ...string) *windows.Proc {
	for _, n := range names {
		if p, err := a.dll.FindProc(n); err == nil {
			return p
		}
	}
	return nil
}

func (a *steamAPI) localSteamID() uint64 {
	user, _, _ := a.steamUser.Call()
	if user == 0 {
		return 0
	}
	id, _, _ := a.getSteamID.Call(user)
	return uint64(id)
}

func (a *steamAPI) netMsgs() uintptr {
	p, _, _ := a.netMessages.Call()
	return p
}

func identityBuf(steamID64 uint64) []byte {
	buf := make([]byte, identityBytes)
	*(*int32)(unsafe.Pointer(&buf[0])) = kIdentitySteamID
	*(*int32)(unsafe.Pointer(&buf[4])) = 8
	*(*uint64)(unsafe.Pointer(&buf[8])) = steamID64
	return buf
}

func (a *steamAPI) accept(peer uint64) {
	msgs := a.netMsgs()
	if msgs == 0 || peer == 0 {
		return
	}
	id := identityBuf(peer)
	a.acceptSession.Call(msgs, uintptr(unsafe.Pointer(&id[0])))
}

func (a *steamAPI) send(peer uint64, payload []byte, channel int) int {
	msgs := a.netMsgs()
	if msgs == 0 {
		return -1
	}
	id := identityBuf(peer)
	var data uintptr
	if len(payload) > 0 {
		data = uintptr(unsafe.Pointer(&payload[0]))
	}
	flags := uintptr(kSendReliable | kSendAutoRestart)
	r, _, _ := a.sendToUser.Call(
		msgs,
		uintptr(unsafe.Pointer(&id[0])),
		data,
		uintptr(len(payload)),
		flags,
		uintptr(channel),
	)
	return int(r)
}

func (a *steamAPI) autoPeer(appID uint32, selfID uint64) uint64 {
	friends, _, _ := a.steamFriends.Call()
	if friends == 0 {
		return 0
	}
	n, _, _ := a.friendCount.Call(friends, uintptr(kFriendFlagImmediate))
	var candidates []uint64
	for i := 0; i < int(n); i++ {
		fid, _, _ := a.friendByIndex.Call(friends, uintptr(i), uintptr(kFriendFlagImmediate))
		id := uint64(fid)
		if id == 0 || id == selfID {
			continue
		}
		var info [40]byte // FriendGameInfo_t ~32–40 bytes
		ok, _, _ := a.friendGame.Call(friends, fid, uintptr(unsafe.Pointer(&info[0])))
		if ok == 0 {
			continue
		}
		gameID := *(*uint64)(unsafe.Pointer(&info[0]))
		if uint32(gameID&0xFFFFFF) != appID {
			continue
		}
		namePtr, _, _ := a.friendName.Call(friends, fid)
		name := cString(namePtr)
		if name == "" {
			name = "friend"
		}
		log.Printf("steam friend playing Remnant II: %s (%d)", name, id)
		candidates = append(candidates, id)
	}
	if len(candidates) == 1 {
		log.Printf("auto-selected sole friend playing Remnant II as peer")
		return candidates[0]
	}
	if len(candidates) > 1 {
		log.Printf("vários friends no Remnant — grave um SteamID64 em steam_peer.txt ou use -peer")
	}
	return 0
}

func cString(ptr uintptr) string {
	if ptr == 0 {
		return ""
	}
	var b []byte
	for {
		c := *(*byte)(unsafe.Pointer(ptr + uintptr(len(b))))
		if c == 0 {
			break
		}
		b = append(b, c)
		if len(b) > 256 {
			break
		}
	}
	return string(b)
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
	if peer == 0 && t.opts.PeerFile != "" {
		if b, err := os.ReadFile(t.opts.PeerFile); err == nil {
			if p := parseSteamID64(string(b)); p != 0 {
				t.mu.Lock()
				t.peer = p
				peer = p
				t.mu.Unlock()
				log.Printf("steam peer loaded from file: %d", p)
				t.api.accept(p)
			}
		}
	}
	if peer == 0 {
		return fmt.Errorf("sem peer Steam ainda (steam_peer.txt / -peer / friend auto)")
	}
	rc := t.api.send(peer, payload, t.opts.Channel)
	if rc != kEResultOK {
		return fmt.Errorf("SendMessageToUser EResult=%d", rc)
	}
	return nil
}

type callbackMsg struct {
	hUser    int32
	callback int32
	param    uintptr
	cubParam int32
}

func (t *steamTransport) pumpCallbacks() {
	pipe, _, _ := t.api.getPipe.Call()
	t.api.manualRun.Call(pipe)
	for {
		var msg callbackMsg
		ok, _, _ := t.api.manualNext.Call(pipe, uintptr(unsafe.Pointer(&msg)))
		if ok == 0 {
			break
		}
		if msg.callback == kNetMsgCallbacks+1 && msg.cubParam >= int32(identityBytes) && msg.param != 0 {
			// SteamNetworkingMessagesSessionRequest_t { SteamNetworkingIdentity m_identityRemote }
			peer := *(*uint64)(unsafe.Pointer(msg.param + 8))
			if peer != 0 {
				t.api.accept(peer)
				t.mu.Lock()
				if t.peer == 0 {
					t.peer = peer
					log.Printf("steam accepted inbound session peer=%d", peer)
					if t.opts.PeerFile != "" {
						_ = os.WriteFile(t.opts.PeerFile, []byte(strconv.FormatUint(peer, 10)+"\n"), 0o644)
					}
				}
				t.mu.Unlock()
			}
		}
		t.api.manualFree.Call(pipe)
	}
}

func (t *steamTransport) recvLoop() {
	defer t.wg.Done()
	var msgPtrs [32]uintptr
	ticker := time.NewTicker(15 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-t.closed:
			return
		case <-ticker.C:
		}
		t.pumpCallbacks()

		msgs := t.api.netMsgs()
		if msgs == 0 {
			continue
		}
		n, _, _ := t.api.recvOnChannel.Call(
			msgs,
			uintptr(t.opts.Channel),
			uintptr(unsafe.Pointer(&msgPtrs[0])),
			uintptr(len(msgPtrs)),
		)
		count := int(n)
		if count <= 0 {
			continue
		}
		for i := 0; i < count; i++ {
			mp := msgPtrs[i]
			if mp == 0 {
				continue
			}
			pData := *(*uintptr)(unsafe.Pointer(mp))
			cbSize := *(*int32)(unsafe.Pointer(mp + 8))
			if pData != 0 && cbSize > 0 {
				payload := unsafe.Slice((*byte)(unsafe.Pointer(pData)), int(cbSize))
				cp := make([]byte, len(payload))
				copy(cp, payload)
				writeInbox(t.opts.Inbox, cp)
				// identity at offset 16; steamID64 at identity+8
				peer := *(*uint64)(unsafe.Pointer(mp + 16 + 8))
				if peer != 0 {
					t.mu.Lock()
					if t.peer == 0 {
						t.peer = peer
						log.Printf("steam learned peer from message: %d", peer)
					}
					t.mu.Unlock()
				}
			}
			t.releaseMsg(mp)
			msgPtrs[i] = 0
		}
	}
}

func (t *steamTransport) releaseMsg(mp uintptr) {
	if t.api.releaseMessage != nil {
		t.api.releaseMessage.Call(mp)
		return
	}
	// m_pfnRelease is after: pData(8)+cbSize(4)+pad/conn(4)+identity(136)+connUser(8)+time(8)+msgNum(8)+freeData(8) = 184
	const releaseFnOff = 8 + 4 + 4 + identityBytes + 8 + 8 + 8 + 8
	fn := *(*uintptr)(unsafe.Pointer(mp + releaseFnOff))
	if fn != 0 {
		syscall.Syscall(fn, 1, mp, 0, 0)
	}
}

func (t *steamTransport) Close() error {
	select {
	case <-t.closed:
	default:
		close(t.closed)
	}
	t.wg.Wait()
	if t.api != nil {
		t.api.shutdown.Call()
		t.api.dll.Release()
		t.api = nil
	}
	return nil
}
