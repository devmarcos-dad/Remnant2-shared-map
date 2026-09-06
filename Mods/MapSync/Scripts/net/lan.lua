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
    LastHelloAt = 0,
    LastFogSent = nil,
    LastTileFingerprint = nil,
}

local function refresh_role()
    local mode = NetMode.detect()
    Status.NetMode = mode
    Lan.Role = NetMode.role_label(mode)
    return mode
end

local function maybe_hello()
    local now = os.time()
    local every = math.floor(((Config.Lan and Config.Lan.HelloIntervalMs) or 2000) / 1000)
    if every < 1 then every = 2 end
    if now - (Lan.LastHelloAt or 0) >= every then
        Queue.send_hello(Lan.Role)
        Lan.LastHelloAt = now
    end
end

local function handle_message(msg)
    if msg.kind == "HELLO" then
        Lan.PeerSeen = true
        Status.Lan = "Connected"
        Status.set("Connected", string.format("peer=%s", tostring(msg.role)))
        return
    end
    if msg.kind == "BYE" then
        Lan.PeerSeen = false
        Status.Lan = "Searching"
        Status.set("Searching", "peer left")
        return
    end
    if msg.kind == "FOG" then
        local ok, detail = FoW.apply_fog_state(msg.enabled)
        if ok then
            Lan.Applied = Lan.Applied + 1
            Status.set("Syncing", string.format("fog=%s applied=%d", tostring(msg.enabled), Lan.Applied))
            Util.log("applied FOG enabled=%s", tostring(msg.enabled))
        else
            Util.log("apply FOG failed: %s", tostring(detail))
        end
        return
    end
    if msg.kind == "TILE" then
        if FoW.reveal_tile(msg.zone, msg.x, msg.y) then
            Lan.Applied = Lan.Applied + 1
            Status.set("Syncing", string.format("applied=%d", Lan.Applied))
        end
        return
    end
    if msg.kind == "TILES" then
        for _, t in ipairs(msg.tiles or {}) do
            if FoW.reveal_tile(t.zone, t.x, t.y) then
                Lan.Applied = Lan.Applied + 1
            end
        end
        Status.set("Syncing", string.format("applied=%d", Lan.Applied))
    end
end

local function host_tick()
    maybe_hello()
    if Config.SyncFogEnabled ~= false then
        local enabled = FoW.get_fog_enabled()
        if enabled ~= nil and enabled ~= Lan.LastFogSent then
            Queue.send_fog(enabled)
            Lan.LastFogSent = enabled
            Lan.Sent = Lan.Sent + 1
            Util.log("host sent FOG enabled=%s", tostring(enabled))
            Status.set("Syncing", string.format("sent fog=%s", tostring(enabled)))
        end
    end
    if Config.SyncTiles ~= false then
        local tiles = FoW.collect_revealed_tiles() or {}
        local fp = FoW.tile_fingerprint(tiles)
        if fp ~= Lan.LastTileFingerprint and #tiles > 0 then
            local maxn = Config.MaxTilesPerPacket or 48
            local chunk = {}
            for i, t in ipairs(tiles) do
                table.insert(chunk, t)
                if #chunk >= maxn or i == #tiles then
                    Queue.send_tiles(chunk)
                    Lan.Sent = Lan.Sent + #chunk
                    chunk = {}
                end
            end
            Lan.LastTileFingerprint = fp
            Util.log("host sent tiles count=%d fp=%s", #tiles, fp)
            Status.set("Syncing", string.format("sent tiles=%d", #tiles))
        end
    end
end

local function client_tick()
    maybe_hello()
    if not Lan.PeerSeen then
        Status.Lan = "Searching"
        if Status.State ~= "Searching" and Status.State ~= "Syncing" and Status.State ~= "Connected" then
            Status.set("Searching", "waiting host")
        end
    end
end

local function tick()
    refresh_role()
    for _, msg in ipairs(Queue.poll_inbox()) do
        handle_message(msg)
    end
    if Lan.Role == "Host" or Lan.Role == "Solo" then
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
        Util.log("LAN not started: %s", tostring(reason))
        Status.Lan = "Off"
        return false
    end
    Queue.init()
    FoW.ensure_bound()
    Lan.Active = true
    refresh_role()
    Status.Lan = "Searching"
    Status.set("Searching", "LAN queue active — start lan_bridge on BOTH PCs")
    Util.log("LAN started role=%s queue=%s", Lan.Role, tostring(Queue.Dir))

    local poll_ms = (Config.Lan and Config.Lan.PollMs) or 750
    if LoopAsync ~= nil then
        LoopAsync(poll_ms, function()
            if not Lan.Active then return true end
            local ok_tick, err = pcall(tick)
            if not ok_tick then Util.log("LAN tick error: %s", tostring(err)) end
            return false
        end)
    else
        Util.log("%s", "LoopAsync missing; LAN poll loop unavailable")
    end
    return true
end

function Lan.stop()
    if Lan.Active then Queue.send_bye(Lan.Role) end
    Lan.Active = false
    Status.Lan = "Off"
    Status.set("Offline", "LAN stopped")
end

function Lan.debug_dump()
    local mode = refresh_role()
    Util.log(
        "LAN active=%s role=%s peer=%s sent=%d applied=%d mode=%s enable=%s fow=%s fog=%s",
        tostring(Lan.Active), Lan.Role, tostring(Lan.PeerSeen),
        Lan.Sent, Lan.Applied, tostring(mode),
        tostring(Config.EnableLanSync), tostring(FoW.Viable),
        tostring(FoW.get_fog_enabled())
    )
    Status.print_screen(3.0)
    return mode
end

return Lan
