local Util = require("lib.util")
local Status = require("lib.status")
local NetMode = require("lib.netmode")
local Config = require("config")
local FoW = require("fow")
local Queue = require("net.queue")

local Lan = {
    Active = false,
    Role = "Unknown",
    PeerSeen = false,
    Applied = 0,
    Sent = 0,
    SentFog = 0,
    SentTiles = 0,
    SentPos = 0,
    AppliedFog = 0,
    AppliedTiles = 0,
    AppliedPos = 0,
    LastHelloAt = 0,
    LastHelloLogAt = 0,
    LastFogSent = nil,
    LastTileFingerprint = nil,
    LastPosAtMs = 0,
    LastError = nil,
    LastTileCount = 0,
    LastForceSyncAt = 0,
    LoopStarted = false,
}

local TAG = "LAN"

local function log(fmt, ...)
    Util.flog(TAG, fmt, ...)
end

local function now_ms()
    return math.floor(os.clock() * 1000)
end

local function transport_name()
    return tostring(Config.Transport or "lan")
end

local function bidirectional_enabled()
    return Config.BidirectionalSync ~= false
end

local function should_emit_map()
    if Lan.Role == "Host" or Lan.Role == "Solo" or Lan.Role == "Unknown" then
        return true
    end
    -- Client emits when bidirectional sync is on.
    return bidirectional_enabled()
end

local function should_emit_fog()
    -- Fog enable/disable stays host-authoritative to avoid Host↔Client fights.
    return Lan.Role == "Host" or Lan.Role == "Solo"
end

local function refresh_role()
    local mode = NetMode.detect()
    Status.NetMode = mode
    Lan.Role = NetMode.role_label(mode)
    return mode
end

local function maybe_hello()
    local now = os.time()
    local every = math.floor(((Config.Lan and Config.Lan.HelloIntervalMs) or 5000) / 1000)
    if every < 1 then every = 5 end
    if now - (Lan.LastHelloAt or 0) >= every then
        local ok = Queue.send_hello(Lan.Role)
        if not ok then
            Lan.LastError = "hello-outbox-write-fail"
            log("outbox write fail HELLO")
        elseif now - (Lan.LastHelloLogAt or 0) >= 15 then
            -- Throttle HELLO logs; was spamming UE4SS console every second.
            log("send HELLO role=%s transport=%s", tostring(Lan.Role), transport_name())
            Lan.LastHelloLogAt = now
        end
        Lan.LastHelloAt = now
    end
end

local function send_tiles(force)
    if Config.SyncTiles == false then return 0 end
    local tiles = FoW.collect_revealed_tiles() or {}
    Lan.LastTileCount = #tiles
    local fp = FoW.tile_fingerprint(tiles)
    if not force and fp == Lan.LastTileFingerprint then return 0 end
    if #tiles == 0 then
        log("TILES n=0 reason=%s (will rely on POS if enabled)", tostring(FoW.last_collect_reason))
        Lan.LastTileFingerprint = fp
        return 0
    end

    local maxn = Config.MaxTilesPerPacket or 48
    local chunk = {}
    local sent_n = 0
    for i, t in ipairs(tiles) do
        table.insert(chunk, t)
        if #chunk >= maxn or i == #tiles then
            local ok = Queue.send_tiles(chunk)
            if not ok then
                Lan.LastError = "tiles-outbox-write-fail"
                log("outbox write fail TILES")
            else
                sent_n = sent_n + #chunk
                Lan.Sent = Lan.Sent + #chunk
                Lan.SentTiles = Lan.SentTiles + #chunk
                log("send TILES n=%d force=%s", #chunk, tostring(force == true))
            end
            chunk = {}
        end
    end
    Lan.LastTileFingerprint = fp
    if sent_n > 0 then
        Status.set("Syncing", string.format("sent tiles=%d", sent_n))
    end
    return sent_n
end

local function send_fog(force)
    if Config.SyncFogEnabled == false then return false end
    if not should_emit_fog() then return false end
    local enabled = FoW.get_fog_enabled()
    if enabled == nil then return false end
    if not force and enabled == Lan.LastFogSent then return false end
    local ok = Queue.send_fog(enabled)
    if not ok then
        Lan.LastError = "fog-outbox-write-fail"
        log("outbox write fail FOG")
        return false
    end
    Lan.LastFogSent = enabled
    Lan.Sent = Lan.Sent + 1
    Lan.SentFog = Lan.SentFog + 1
    log("send FOG enabled=%s force=%s", tostring(enabled), tostring(force == true))
    Status.set("Syncing", string.format("sent fog=%s", tostring(enabled)))
    return true
end

local function send_pos(force)
    if Config.SyncHostPositions == false then return false end
    local interval = Config.PositionIntervalMs or Config.HostPositionIntervalMs or 1000
    local now = now_ms()
    if not force and now - (Lan.LastPosAtMs or 0) < interval then return false end
    Lan.LastPosAtMs = now

    local pos = FoW.get_local_pawn_pos()
    if not pos then
        log("POS skip no-pawn")
        return false
    end
    local ok = Queue.send_pos(pos.x, pos.y, pos.z)
    if not ok then
        Lan.LastError = "pos-outbox-write-fail"
        log("outbox write fail POS")
        return false
    end
    Lan.Sent = Lan.Sent + 1
    Lan.SentPos = Lan.SentPos + 1
    log("send POS x=%.1f y=%.1f z=%.1f force=%s", pos.x, pos.y, pos.z or 0, tostring(force == true))
    return true
end

-- Push local exploration to peer. force=true ignores tile fingerprint / POS throttle.
function Lan.push_local_map(opts)
    opts = opts or {}
    local force = opts.force == true
    if not Lan.Active then
        return false, "sync not active"
    end
    if not FoW.Viable then
        return false, "FoW not viable"
    end
    FoW.ensure_bound()
    local tiles_n = 0
    if should_emit_map() or force then
        send_fog(force)
        tiles_n = send_tiles(force)
        send_pos(force)
    end
    return true, tiles_n
end

-- Hotkey / button: push ours and ask peer to push theirs.
function Lan.force_sync()
    if not Lan.Active then
        if Config.EnableLanSync and FoW.Viable then
            Lan.start()
        else
            log("%s", "force_sync ignored — sync not active (F7 first)")
            Status.set("Offline", "force sync needs F7 + bridge")
            return false
        end
    end

    local now = now_ms()
    if now - (Lan.LastForceSyncAt or 0) < 750 then
        log("%s", "force_sync throttled")
        return false
    end
    Lan.LastForceSyncAt = now

    refresh_role()
    Lan.LastTileFingerprint = nil
    Lan.LastFogSent = nil
    Lan.LastPosAtMs = 0

    local ok_push, tiles_n = Lan.push_local_map({ force = true })
    local ok_req = Queue.send_sync_req(Lan.Role)
    if not ok_req then
        Lan.LastError = "sync-req-outbox-write-fail"
        log("%s", "outbox write fail SYNC_REQ")
    else
        Lan.Sent = Lan.Sent + 1
        log("send SYNC_REQ role=%s", tostring(Lan.Role))
    end

    Status.set(
        "Syncing",
        string.format("force push tiles=%s req=%s", tostring(tiles_n or 0), tostring(ok_req))
    )
    log(
        "force_sync role=%s push_ok=%s tiles=%s req_ok=%s peer=%s",
        tostring(Lan.Role),
        tostring(ok_push),
        tostring(tiles_n),
        tostring(ok_req),
        tostring(Lan.PeerSeen)
    )
    return ok_push and ok_req
end

local function handle_message(msg)
    if msg.kind == "HELLO" then
        local first = not Lan.PeerSeen
        Lan.PeerSeen = true
        Status.Lan = "Connected"
        -- Only log/status on first connect or role change — not every HELLO.
        if first then
            Status.set("Connected", string.format("peer=%s", tostring(msg.role)))
            log("recv HELLO peer=%s (connected)", tostring(msg.role))
        end
        return
    end
    if msg.kind == "BYE" then
        Lan.PeerSeen = false
        Status.Lan = "Searching"
        Status.set("Searching", "peer left")
        log("recv BYE peer=%s", tostring(msg.role))
        return
    end
    if msg.kind == "SYNC_REQ" then
        log("recv SYNC_REQ from=%s — pushing local map", tostring(msg.role))
        Lan.LastTileFingerprint = nil
        Lan.LastFogSent = nil
        Lan.LastPosAtMs = 0
        local ok, tiles_n = Lan.push_local_map({ force = true })
        Status.set("Syncing", string.format("answered sync_req tiles=%s", tostring(tiles_n or 0)))
        if not ok then
            log("SYNC_REQ answer failed: %s", tostring(tiles_n))
        end
        return
    end
    if msg.kind == "FOG" then
        local ok, detail = FoW.apply_fog_state(msg.enabled)
        if ok then
            Lan.Applied = Lan.Applied + 1
            Lan.AppliedFog = Lan.AppliedFog + 1
            Status.set("Syncing", string.format("fog=%s applied=%d", tostring(msg.enabled), Lan.Applied))
            log("apply FOG ok enabled=%s", tostring(msg.enabled))
        else
            Lan.LastError = tostring(detail)
            log("apply FOG FAIL %s", tostring(detail))
        end
        return
    end
    if msg.kind == "TILE" then
        local ok, detail = FoW.reveal_tile(msg.zone or 0, msg.x, msg.y)
        if ok then
            Lan.Applied = Lan.Applied + 1
            Lan.AppliedTiles = Lan.AppliedTiles + 1
            Status.set("Syncing", string.format("applied=%d", Lan.Applied))
            log("apply TILE ok %d:%d:%d method=%s", msg.zone or 0, msg.x or 0, msg.y or 0, tostring(detail))
        else
            Lan.LastError = tostring(detail)
            log("apply TILE FAIL %d:%d:%d %s", msg.zone or 0, msg.x or 0, msg.y or 0, tostring(detail))
        end
        return
    end
    if msg.kind == "TILES" then
        local ok_n, fail_n = 0, 0
        for _, t in ipairs(msg.tiles or {}) do
            local ok, detail = FoW.reveal_tile(t.zone or 0, t.x, t.y)
            if ok then
                ok_n = ok_n + 1
                Lan.Applied = Lan.Applied + 1
                Lan.AppliedTiles = Lan.AppliedTiles + 1
            else
                fail_n = fail_n + 1
                Lan.LastError = tostring(detail)
            end
        end
        Status.set("Syncing", string.format("applied=%d", Lan.Applied))
        log("apply TILES ok=%d fail=%d total_applied=%d", ok_n, fail_n, Lan.Applied)
        return
    end
    if msg.kind == "POS" then
        local ok, detail = FoW.reveal_at_world_pos(msg.x, msg.y, msg.z)
        if ok then
            Lan.Applied = Lan.Applied + 1
            Lan.AppliedPos = Lan.AppliedPos + 1
            Status.set("Syncing", string.format("pos applied=%d", Lan.Applied))
            log("apply POS ok x=%.1f y=%.1f z=%.1f method=%s", msg.x or 0, msg.y or 0, msg.z or 0, tostring(detail))
        else
            Lan.LastError = tostring(detail)
            log("apply POS FAIL x=%.1f y=%.1f z=%.1f %s", msg.x or 0, msg.y or 0, msg.z or 0, tostring(detail))
        end
        return
    end
    log("recv UNKNOWN kind=%s", tostring(msg.kind))
end

local function emit_tick()
    maybe_hello()
    if not should_emit_map() then
        return
    end
    -- Periodic fog only from host/solo.
    send_fog(false)
    send_tiles(false)
    send_pos(false)
end

local function tick()
    refresh_role()
    local inbox = Queue.poll_inbox()
    for _, msg in ipairs(inbox) do
        local ok, err = pcall(handle_message, msg)
        if not ok then
            Lan.LastError = tostring(err)
            log("inbox handle fail %s", tostring(err))
        end
    end
    emit_tick()
    if not Lan.PeerSeen then
        Status.Lan = "Searching"
    end
end

function Lan.can_start()
    if not Config.EnableLanSync then
        return false, "EnableLanSync=false"
    end
    if not FoW.Viable then
        return false, "FoW not viable yet (press F7 first)"
    end
    return true, refresh_role()
end

function Lan.start()
    local ok, reason = Lan.can_start()
    if not ok then
        log("not started: %s", tostring(reason))
        Status.Lan = "Off"
        return false
    end
    Queue.init()
    FoW.ensure_bound()
    Lan.Active = true
    refresh_role()
    Status.Lan = "Searching"
    local bridge_hint = "lan_bridge.exe"
    if transport_name() == "steam" or transport_name() == "tcp" then
        bridge_hint = "steam_bridge.exe"
    end
    Status.set(
        "Searching",
        string.format("%s queue — run %s on BOTH PCs", transport_name(), bridge_hint)
    )
    log(
        "started role=%s transport=%s bidirectional=%s queue=%s",
        Lan.Role,
        transport_name(),
        tostring(bidirectional_enabled()),
        tostring(Queue.Dir)
    )
    if Lan.Role == "Unknown" then
        log("role=Unknown — set ForceLanRole=\"Host\" or \"Client\" in config.lua if needed")
    end

    if Lan.LoopStarted then
        return true
    end

    local poll_ms = (Config.Lan and Config.Lan.PollMs) or 1000
    if LoopAsync ~= nil then
        Lan.LoopStarted = true
        LoopAsync(poll_ms, function()
            -- Keep the loop alive so Lan.start() can resume after Lan.stop().
            if not Lan.Active then return false end
            local ok_tick, err = pcall(tick)
            if not ok_tick then
                Lan.LastError = tostring(err)
                log("tick error: %s", tostring(err))
            end
            return false
        end)
    else
        log("%s", "LoopAsync missing; LAN poll loop unavailable")
    end
    return true
end

function Lan.stop()
    if Lan.Active then Queue.send_bye(Lan.Role) end
    Lan.Active = false
    Status.Lan = "Off"
    Status.set("Offline", "sync stopped")
    log("%s", "stopped")
end

-- Call after dungeon ↔ overworld (ClientRestart). Rebind FoW and force a fresh TILES pass.
function Lan.on_world_changed(reason)
    log("world changed reason=%s active=%s", tostring(reason or "?"), tostring(Lan.Active))
    FoW.reset_for_new_world(reason)
    Lan.LastTileFingerprint = nil
    Lan.LastFogSent = nil
    Lan.LastPosAtMs = 0
    Lan.LastTileCount = 0
    refresh_role()
    if Lan.Active then
        Status.set("Syncing", "rebinding after zone change")
        log("rebound after zone change role=%s", tostring(Lan.Role))
        -- After zone change, push immediately so peer catches up.
        Lan.push_local_map({ force = true })
    elseif Config.EnableLanSync and FoW.Viable then
        Lan.start()
    end
end

function Lan.debug_dump()
    local mode = refresh_role()
    log(
        "DUMP active=%s role=%s peer=%s mode=%s enable=%s viable=%s transport=%s bi=%s",
        tostring(Lan.Active),
        tostring(Lan.Role),
        tostring(Lan.PeerSeen),
        tostring(mode),
        tostring(Config.EnableLanSync),
        tostring(FoW.Viable),
        transport_name(),
        tostring(bidirectional_enabled())
    )
    log(
        "DUMP sent fog=%d tiles=%d pos=%d | applied fog=%d tiles=%d pos=%d | last_tiles=%d err=%s",
        Lan.SentFog,
        Lan.SentTiles,
        Lan.SentPos,
        Lan.AppliedFog,
        Lan.AppliedTiles,
        Lan.AppliedPos,
        Lan.LastTileCount,
        tostring(Lan.LastError)
    )
    log("DUMP fow %s", FoW.status_line())
    if FoW.dump_structure then
        FoW.dump_structure()
    end
    Status.print_screen(3.0)
    return mode
end

return Lan
