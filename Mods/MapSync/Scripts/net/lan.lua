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
}

local TAG = "LAN"

local function log(fmt, ...)
    Util.flog(TAG, fmt, ...)
end

local function now_ms()
    return math.floor(os.clock() * 1000)
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
            log("send HELLO role=%s", tostring(Lan.Role))
            Lan.LastHelloLogAt = now
        end
        Lan.LastHelloAt = now
    end
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

local function host_send_fog()
    if Config.SyncFogEnabled == false then return end
    -- Avoid Host↔Client fog fights when NetMode is Unknown on both PCs.
    if Lan.Role == "Unknown" then return end
    local enabled = FoW.get_fog_enabled()
    if enabled ~= nil and enabled ~= Lan.LastFogSent then
        local ok = Queue.send_fog(enabled)
        if not ok then
            Lan.LastError = "fog-outbox-write-fail"
            log("outbox write fail FOG")
            return
        end
        Lan.LastFogSent = enabled
        Lan.Sent = Lan.Sent + 1
        Lan.SentFog = Lan.SentFog + 1
        log("send FOG enabled=%s", tostring(enabled))
        Status.set("Syncing", string.format("sent fog=%s", tostring(enabled)))
    end
end

local function host_send_tiles()
    if Config.SyncTiles == false then return end
    local tiles = FoW.collect_revealed_tiles() or {}
    Lan.LastTileCount = #tiles
    local fp = FoW.tile_fingerprint(tiles)
    if fp == Lan.LastTileFingerprint then return end
    if #tiles == 0 then
        log("TILES n=0 reason=%s (will rely on POS if enabled)", tostring(FoW.last_collect_reason))
        Lan.LastTileFingerprint = fp
        return
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
                log("send TILES n=%d", #chunk)
            end
            chunk = {}
        end
    end
    Lan.LastTileFingerprint = fp
    Status.set("Syncing", string.format("sent tiles=%d", sent_n))
end

local function host_send_pos()
    if Config.SyncHostPositions == false then return end
    local interval = Config.HostPositionIntervalMs or 1000
    local now = now_ms()
    if now - (Lan.LastPosAtMs or 0) < interval then return end
    Lan.LastPosAtMs = now

    local pos = FoW.get_local_pawn_pos()
    if not pos then
        log("POS skip no-pawn")
        return
    end
    local ok = Queue.send_pos(pos.x, pos.y, pos.z)
    if not ok then
        Lan.LastError = "pos-outbox-write-fail"
        log("outbox write fail POS")
        return
    end
    Lan.Sent = Lan.Sent + 1
    Lan.SentPos = Lan.SentPos + 1
    log("send POS x=%.1f y=%.1f z=%.1f", pos.x, pos.y, pos.z or 0)
end

local function host_tick()
    maybe_hello()
    host_send_fog()
    host_send_tiles()
    host_send_pos()
end

local function client_tick()
    maybe_hello()
    if not Lan.PeerSeen then
        Status.Lan = "Searching"
        -- Do not Status.set every tick — that flooded the log/console.
    end
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
    -- Host/Solo emit FOG/TILES/POS. Unknown falls back to host emit so Solo/broken
    -- NetMode still syncs; Client only receives.
    if Lan.Role == "Host" or Lan.Role == "Solo" or Lan.Role == "Unknown" then
        host_tick()
    else
        client_tick()
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
    Status.set("Searching", "LAN queue active — run lan_bridge.exe on BOTH PCs")
    log("started role=%s queue=%s", Lan.Role, tostring(Queue.Dir))
    if Lan.Role == "Unknown" then
        log("role=Unknown — set ForceLanRole=\"Host\" or \"Client\" in config.lua if needed")
    end

    local poll_ms = (Config.Lan and Config.Lan.PollMs) or 1000
    if LoopAsync ~= nil then
        LoopAsync(poll_ms, function()
            if not Lan.Active then return true end
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
    Status.set("Offline", "LAN stopped")
    log("%s", "stopped")
end

function Lan.debug_dump()
    local mode = refresh_role()
    log(
        "DUMP active=%s role=%s peer=%s mode=%s enable=%s viable=%s",
        tostring(Lan.Active),
        tostring(Lan.Role),
        tostring(Lan.PeerSeen),
        tostring(mode),
        tostring(Config.EnableLanSync),
        tostring(FoW.Viable)
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
