package main

import (
	"bufio"
	"encoding/binary"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// steam_bridge shuttles MapSync queue files over Steam P2P (when Steamworks is
// linked) or a TCP fallback for WAN testing. Same queue contract as lan_bridge:
//
//	%TEMP%\MapSyncQueue\outbox\*.msg  -> ship to peer
//	%TEMP%\MapSyncQueue\inbox\*.msg   <- received payloads for the Lua mod
//
// Modes:
//
//	steam  — ISteamNetworkingMessages P2P (requires -tags steamworks build)
//	tcp    — direct TCP listen/dial (diagnostic / no-SDK fallback)
//	lan    — UDP broadcast helper (prefer tools/lan_bridge/lan_bridge.exe)
func main() {
	queueName := flag.String("queue", "MapSyncQueue", "queue directory name under %TEMP%")
	mode := flag.String("mode", "tcp", "transport: steam | tcp | lan")
	poll := flag.Duration("poll", 250*time.Millisecond, "outbox poll interval")
	appID := flag.Uint("appid", 1282100, "Steam AppID (Remnant II = 1282100)")
	peerID := flag.String("peer", "", "partner SteamID64 (or leave empty to read steam_peer.txt / auto-discover)")
	listen := flag.String("listen", "", "TCP listen addr (-mode tcp), e.g. :27073")
	dial := flag.String("dial", "", "TCP dial addr (-mode tcp), e.g. 1.2.3.4:27073")
	udpPort := flag.Int("udp", 27071, "UDP data port (-mode lan)")
	broadcastPort := flag.Int("broadcast", 27072, "UDP discovery port (-mode lan)")
	channel := flag.Int("channel", 1, "Steam networking channel (both peers must match)")
	flag.Parse()

	temp := os.Getenv("TEMP")
	if temp == "" {
		temp = os.Getenv("TMP")
	}
	if temp == "" {
		temp = "."
	}
	queueDir := filepath.Join(temp, *queueName)
	outbox := filepath.Join(queueDir, "outbox")
	inbox := filepath.Join(queueDir, "inbox")
	mustMkdir(outbox)
	mustMkdir(inbox)

	peerFile := filepath.Join(queueDir, "steam_peer.txt")
	if strings.TrimSpace(*peerID) == "" {
		if b, err := os.ReadFile(peerFile); err == nil {
			*peerID = strings.TrimSpace(string(b))
		}
	}

	log.Printf("MapSync steam_bridge starting")
	log.Printf("mode=%s queue=%s appid=%d channel=%d", *mode, queueDir, *appID, *channel)
	if *peerID != "" {
		log.Printf("peer=%s", *peerID)
	} else {
		log.Printf("peer not set — will try friend auto-discover (steam) or read %s / -peer", peerFile)
	}

	var transport Transport
	var err error
	switch strings.ToLower(*mode) {
	case "steam":
		transport, err = newSteamTransport(steamOpts{
			AppID:    uint32(*appID),
			PeerID:   *peerID,
			Channel:  *channel,
			Inbox:    inbox,
			QueueDir: queueDir,
			PeerFile: peerFile,
		})
	case "tcp":
		listenAddr := *listen
		dialAddr := *dial
		// Default to listener when neither flag is set (typical host PC).
		if listenAddr == "" && dialAddr == "" {
			listenAddr = ":27073"
		}
		transport, err = newTCPTransport(tcpOpts{
			Listen: listenAddr,
			Dial:   dialAddr,
			Inbox:  inbox,
		})
	case "lan":
		transport, err = newLANTransport(lanOpts{
			UDPPort:       *udpPort,
			BroadcastPort: *broadcastPort,
			Inbox:         inbox,
		})
	default:
		log.Fatalf("unknown -mode %q (use steam|tcp|lan)", *mode)
	}
	if err != nil {
		log.Fatalf("transport init: %v", err)
	}
	defer transport.Close()

	log.Printf("transport ready: %s", transport.Name())
	runOutboxLoop(outbox, transport, *poll)
}

type Transport interface {
	Name() string
	Send(payload []byte) error
	Close() error
}

func mustMkdir(path string) {
	if err := os.MkdirAll(path, 0o755); err != nil {
		log.Fatalf("mkdir %s: %v", path, err)
	}
}

func writeInbox(inbox string, payload []byte) {
	name := fmt.Sprintf("%d_%d.msg", time.Now().Unix(), time.Now().UnixNano()%1_000_000)
	path := filepath.Join(inbox, name)
	if err := os.WriteFile(path, payload, 0o644); err != nil {
		log.Printf("inbox write fail: %v", err)
	}
}

func runOutboxLoop(outbox string, transport Transport, poll time.Duration) {
	seen := map[string]struct{}{}
	for {
		entries, err := os.ReadDir(outbox)
		if err == nil {
			for _, e := range entries {
				if e.IsDir() || !strings.HasSuffix(e.Name(), ".msg") {
					continue
				}
				full := filepath.Join(outbox, e.Name())
				if _, ok := seen[full]; ok {
					continue
				}
				data, err := os.ReadFile(full)
				if err != nil {
					continue
				}
				seen[full] = struct{}{}
				if err := transport.Send(data); err != nil {
					log.Printf("send %s failed: %v", e.Name(), err)
					delete(seen, full) // retry next poll
					continue
				}
				_ = os.Remove(full)
				log.Printf("shipped %s (%d bytes) via %s", e.Name(), len(data), transport.Name())
			}
		}
		time.Sleep(poll)
	}
}

// --- TCP transport (WAN test without Steamworks) --------------------------------

type tcpOpts struct {
	Listen string
	Dial   string
	Inbox  string
}

type tcpTransport struct {
	inbox string
	mu    sync.Mutex
	conns map[net.Conn]struct{}
	ln    net.Listener
}

func newTCPTransport(opts tcpOpts) (Transport, error) {
	t := &tcpTransport{
		inbox: opts.Inbox,
		conns: map[net.Conn]struct{}{},
	}
	if opts.Listen != "" {
		ln, err := net.Listen("tcp", opts.Listen)
		if err != nil {
			return nil, fmt.Errorf("tcp listen %s: %w", opts.Listen, err)
		}
		t.ln = ln
		log.Printf("tcp listening on %s", opts.Listen)
		go t.acceptLoop()
	}
	if opts.Dial != "" {
		go t.dialLoop(opts.Dial)
	}
	if opts.Listen == "" && opts.Dial == "" {
		return nil, fmt.Errorf("tcp mode needs -listen and/or -dial")
	}
	return t, nil
}

func (t *tcpTransport) Name() string { return "tcp" }

func (t *tcpTransport) acceptLoop() {
	for {
		c, err := t.ln.Accept()
		if err != nil {
			return
		}
		log.Printf("tcp peer connected %s", c.RemoteAddr())
		t.addConn(c)
		go t.readLoop(c)
	}
}

func (t *tcpTransport) dialLoop(addr string) {
	for {
		c, err := net.DialTimeout("tcp", addr, 5*time.Second)
		if err != nil {
			log.Printf("tcp dial %s: %v (retry)", addr, err)
			time.Sleep(3 * time.Second)
			continue
		}
		log.Printf("tcp dialed %s", addr)
		t.addConn(c)
		t.readLoop(c)
		log.Printf("tcp dial connection closed; reconnecting")
		time.Sleep(2 * time.Second)
	}
}

func (t *tcpTransport) addConn(c net.Conn) {
	t.mu.Lock()
	t.conns[c] = struct{}{}
	t.mu.Unlock()
}

func (t *tcpTransport) removeConn(c net.Conn) {
	t.mu.Lock()
	delete(t.conns, c)
	t.mu.Unlock()
	_ = c.Close()
}

func (t *tcpTransport) readLoop(c net.Conn) {
	defer t.removeConn(c)
	r := bufio.NewReader(c)
	for {
		var n uint32
		if err := binary.Read(r, binary.BigEndian, &n); err != nil {
			return
		}
		if n == 0 || n > 4*1024*1024 {
			log.Printf("tcp bad frame size %d", n)
			return
		}
		buf := make([]byte, n)
		if _, err := io.ReadFull(r, buf); err != nil {
			return
		}
		writeInbox(t.inbox, buf)
	}
}

func (t *tcpTransport) Send(payload []byte) error {
	frame := make([]byte, 4+len(payload))
	binary.BigEndian.PutUint32(frame[:4], uint32(len(payload)))
	copy(frame[4:], payload)

	t.mu.Lock()
	defer t.mu.Unlock()
	if len(t.conns) == 0 {
		return fmt.Errorf("no tcp peers connected")
	}
	var last error
	for c := range t.conns {
		_ = c.SetWriteDeadline(time.Now().Add(5 * time.Second))
		if _, err := c.Write(frame); err != nil {
			last = err
			log.Printf("tcp write fail %s: %v", c.RemoteAddr(), err)
		}
	}
	return last
}

func (t *tcpTransport) Close() error {
	if t.ln != nil {
		_ = t.ln.Close()
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	for c := range t.conns {
		_ = c.Close()
	}
	t.conns = map[net.Conn]struct{}{}
	return nil
}

// --- LAN transport (optional; lan_bridge.exe is preferred for same-house) --------

type lanOpts struct {
	UDPPort       int
	BroadcastPort int
	Inbox         string
}

type lanTransport struct {
	udpPort int
	inbox   string
	peersMu sync.Mutex
	peers   map[string]time.Time
	pc      net.PacketConn
}

func newLANTransport(opts lanOpts) (Transport, error) {
	t := &lanTransport{
		udpPort: opts.UDPPort,
		inbox:   opts.Inbox,
		peers:   map[string]time.Time{},
	}
	pc, err := net.ListenPacket("udp4", fmt.Sprintf(":%d", opts.UDPPort))
	if err != nil {
		return nil, err
	}
	t.pc = pc
	go t.listenData()
	go t.listenBroadcast(opts.BroadcastPort)
	go t.announce(opts.BroadcastPort)
	return t, nil
}

func (t *lanTransport) Name() string { return "lan" }

func (t *lanTransport) listenData() {
	buf := make([]byte, 64*1024)
	for {
		n, addr, err := t.pc.ReadFrom(buf)
		if err != nil {
			return
		}
		t.peersMu.Lock()
		t.peers[addr.String()] = time.Now()
		t.peersMu.Unlock()
		writeInbox(t.inbox, append([]byte(nil), buf[:n]...))
	}
}

func (t *lanTransport) listenBroadcast(broadcastPort int) {
	pc, err := net.ListenPacket("udp4", fmt.Sprintf(":%d", broadcastPort))
	if err != nil {
		log.Printf("lan broadcast listen: %v", err)
		return
	}
	buf := make([]byte, 1024)
	for {
		n, addr, err := pc.ReadFrom(buf)
		if err != nil {
			return
		}
		msg := string(buf[:n])
		if !strings.HasPrefix(msg, "MAPSYNC_HELLO|") {
			continue
		}
		parts := strings.Split(strings.TrimSpace(msg), "|")
		peerPort := t.udpPort
		if len(parts) >= 3 {
			fmt.Sscanf(parts[2], "%d", &peerPort)
		}
		host, _, err := net.SplitHostPort(addr.String())
		if err != nil {
			host = addr.String()
		}
		t.peersMu.Lock()
		t.peers[fmt.Sprintf("%s:%d", host, peerPort)] = time.Now()
		t.peersMu.Unlock()
	}
}

func (t *lanTransport) announce(broadcastPort int) {
	addr, err := net.ResolveUDPAddr("udp4", fmt.Sprintf("255.255.255.255:%d", broadcastPort))
	if err != nil {
		return
	}
	conn, err := net.DialUDP("udp4", nil, addr)
	if err != nil {
		return
	}
	defer conn.Close()
	payload := []byte(fmt.Sprintf("MAPSYNC_HELLO|1|%d", t.udpPort))
	for {
		_, _ = conn.Write(payload)
		time.Sleep(2 * time.Second)
	}
}

func (t *lanTransport) Send(payload []byte) error {
	t.peersMu.Lock()
	addrs := make([]string, 0, len(t.peers))
	now := time.Now()
	for addr, ts := range t.peers {
		if now.Sub(ts) > 30*time.Second {
			delete(t.peers, addr)
			continue
		}
		addrs = append(addrs, addr)
	}
	t.peersMu.Unlock()

	if len(addrs) == 0 {
		addr, err := net.ResolveUDPAddr("udp4", fmt.Sprintf("255.255.255.255:%d", t.udpPort))
		if err != nil {
			return err
		}
		_, err = t.pc.WriteTo(payload, addr)
		return err
	}
	var last error
	for _, a := range addrs {
		raddr, err := net.ResolveUDPAddr("udp4", a)
		if err != nil {
			last = err
			continue
		}
		if _, err := t.pc.WriteTo(payload, raddr); err != nil {
			last = err
		}
	}
	return last
}

func (t *lanTransport) Close() error {
	if t.pc != nil {
		return t.pc.Close()
	}
	return nil
}
