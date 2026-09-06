package main

import (
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

// lan_bridge shuttles MapSync queue files over UDP on the LAN.
// Layout expected under queue dir:
//
//	outbox/*.msg  -> broadcast/send
//	inbox/*.msg   <- received datagrams
func main() {
	queueName := flag.String("queue", "MapSyncQueue", "queue directory name under %TEMP%")
	udpPort := flag.Int("udp", 27071, "UDP listen/send port")
	broadcastPort := flag.Int("broadcast", 27072, "UDP broadcast discovery port")
	poll := flag.Duration("poll", 250*time.Millisecond, "outbox poll interval")
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

	log.Printf("MapSync lan_bridge starting")
	log.Printf("queue=%s udp=%d broadcast=%d", queueDir, *udpPort, *broadcastPort)

	var peersMu sync.Mutex
	peers := map[string]time.Time{}

	go listenUDP(*udpPort, inbox, func(addr string) {
		peersMu.Lock()
		peers[addr] = time.Now()
		peersMu.Unlock()
	})
	go listenBroadcast(*broadcastPort, *udpPort, func(addr string) {
		peersMu.Lock()
		peers[addr] = time.Now()
		peersMu.Unlock()
		log.Printf("peer discovered %s", addr)
	})
	go announce(*broadcastPort, *udpPort)

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
				peersMu.Lock()
				addrs := make([]string, 0, len(peers))
				now := time.Now()
				for addr, ts := range peers {
					if now.Sub(ts) > 30*time.Second {
						delete(peers, addr)
						continue
					}
					addrs = append(addrs, addr)
				}
				peersMu.Unlock()

				if len(addrs) == 0 {
					// No peers yet: broadcast payload on data port too.
					_ = sendBroadcast(*udpPort, data)
				} else {
					for _, addr := range addrs {
						if err := sendTo(addr, data); err != nil {
							log.Printf("send %s failed: %v", addr, err)
						}
					}
				}
				_ = os.Remove(full)
				log.Printf("shipped %s (%d bytes) peers=%d", e.Name(), len(data), len(addrs))
			}
		}
		time.Sleep(*poll)
	}
}

func mustMkdir(path string) {
	if err := os.MkdirAll(path, 0o755); err != nil {
		log.Fatalf("mkdir %s: %v", path, err)
	}
}

func listenUDP(port int, inbox string, onPeer func(string)) {
	pc, err := net.ListenPacket("udp4", fmt.Sprintf(":%d", port))
	if err != nil {
		log.Fatalf("listen udp %d: %v", port, err)
	}
	buf := make([]byte, 64*1024)
	for {
		n, addr, err := pc.ReadFrom(buf)
		if err != nil {
			continue
		}
		onPeer(addr.String())
		name := fmt.Sprintf("%d_%d.msg", time.Now().Unix(), time.Now().UnixNano()%1_000_000)
		path := filepath.Join(inbox, name)
		_ = os.WriteFile(path, append([]byte(nil), buf[:n]...), 0o644)
	}
}

func listenBroadcast(broadcastPort, dataPort int, onPeer func(string)) {
	pc, err := net.ListenPacket("udp4", fmt.Sprintf(":%d", broadcastPort))
	if err != nil {
		log.Fatalf("listen broadcast %d: %v", broadcastPort, err)
	}
	buf := make([]byte, 1024)
	for {
		n, addr, err := pc.ReadFrom(buf)
		if err != nil {
			continue
		}
		msg := string(buf[:n])
		if !strings.HasPrefix(msg, "MAPSYNC_HELLO|") {
			continue
		}
		// Prefer peer's advertised data port if present.
		parts := strings.Split(strings.TrimSpace(msg), "|")
		peerPort := dataPort
		if len(parts) >= 3 {
			fmt.Sscanf(parts[2], "%d", &peerPort)
		}
		host, _, err := net.SplitHostPort(addr.String())
		if err != nil {
			host = addr.String()
		}
		onPeer(fmt.Sprintf("%s:%d", host, peerPort))
	}
}

func announce(broadcastPort, dataPort int) {
	addr, err := net.ResolveUDPAddr("udp4", fmt.Sprintf("255.255.255.255:%d", broadcastPort))
	if err != nil {
		log.Printf("resolve broadcast: %v", err)
		return
	}
	conn, err := net.DialUDP("udp4", nil, addr)
	if err != nil {
		log.Printf("dial broadcast: %v", err)
		return
	}
	defer conn.Close()
	payload := []byte(fmt.Sprintf("MAPSYNC_HELLO|1|%d", dataPort))
	for {
		_, _ = conn.Write(payload)
		time.Sleep(2 * time.Second)
	}
}

func sendBroadcast(port int, data []byte) error {
	addr, err := net.ResolveUDPAddr("udp4", fmt.Sprintf("255.255.255.255:%d", port))
	if err != nil {
		return err
	}
	conn, err := net.DialUDP("udp4", nil, addr)
	if err != nil {
		return err
	}
	defer conn.Close()
	_, err = conn.Write(data)
	return err
}

func sendTo(addr string, data []byte) error {
	raddr, err := net.ResolveUDPAddr("udp4", addr)
	if err != nil {
		return err
	}
	conn, err := net.DialUDP("udp4", nil, raddr)
	if err != nil {
		return err
	}
	defer conn.Close()
	_, err = io.Copy(conn, strings.NewReader(string(data)))
	if err != nil {
		_, err = conn.Write(data)
	}
	return err
}
