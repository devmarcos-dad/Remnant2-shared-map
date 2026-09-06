local Util = require("lib.util")
local Status = require("lib.status")
local NetMode = require("lib.netmode")
local Config = require("config")
local FoW = require("fow")
local Queue = require("net.queue")
local Protocol = require("net.protocol")

local Lan = {
    Active = false,
    Role = "Unknown",
    PeerSeen = false,
    Applied = 0,
    Sent = 0,
}

local function refresh_role()
    local mode = NetMode.detect()
    Status.NetMode = mode
    Lan.Role = NetMode.role_label(mode)
    return mode
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
    if msg.kind == "TILE" then
        local ok, detail = FoW.reveal_tile(msg.zone, msg.x, msg.y)
        if ok then
            Lan.Applied = Lan.Applied + 1
            Status.set("Syncing", string.format("applied=%d", Lan.Applied))
        else
            Util.log("apply tile failed: %s", tostring(detail))
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
    local data, err = FoW.read_revealed_tiles()
    if data == nil then
        Queue.send_hello("Host")
        return
    end

    local tiles = {}
    pcall(function()
        if type(data) == "table" then
            for _, entry in pairs(data) do
                if type(entry) == "table" then
                    table.insert(tiles, {
                        zone = entry.ZoneID or entry.zone or entry.Zone or 0,
                        x = entry.X or entry.x or 0,
                        y = entry.Y or entry.y or 0,
                    })
                end
            end
        end
    end)

    if #tiles > 0 then
        local chunk = {}
        for i, t in ipairs(tiles) do
            table.insert(chunk, t)
            if #chunk >= 64 or i == #tiles then
                Queue.send_tiles(chunk)
                Lan.Sent = Lan.Sent + #chunk
                chunk = {}
            end
        end
        Status.set("Syncing", string.format("sent=%d", Lan.Sent))
    else
        Queue.send_hello("Host")
        if err then Util.log("host read tiles: %s", tostring(err)) end
    end
end

local function client_tick()
    for _, msg in ipairs(Queue.poll_inbox()) do
        handle_message(msg)
    end
    if not Lan.PeerSeen then
        Queue.send_hello("Client")
        Status.Lan = "Searching"
        if Status.State ~= "Searching" and Status.State ~= "Syncing" and Status.State ~= "Connected" then
            Status.set("Searching", "waiting host")
        end
    end
end

function Lan.can_start()
    if not Config.EnableLanSync then
        return false, "EnableLanSync=false"
    end
    if not FoW.Viable then
        return false, "FoW not viable yet"
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
    Lan.Active = true
    refresh_role()
    Status.Lan = "Searching"
    Status.set("Searching", "LAN queue active")
    Util.log("LAN started role=%s queue=%s", Lan.Role, tostring(Queue.Dir))
    Util.log("%s", "Run tools/lan_bridge on BOTH PCs (see README).")

    local poll_ms = (Config.Lan and Config.Lan.PollMs) or 500
    if LoopAsync ~= nil then
        LoopAsync(poll_ms, function()
            if not Lan.Active then return true end
            refresh_role()
            if Lan.Role == "Host" then
                host_tick()
            else
                client_tick()
            end
            for _, msg in ipairs(Queue.poll_inbox()) do
                handle_message(msg)
            end
            return false
        end)
    else
        Util.log("%s", "LoopAsync missing; LAN poll loop unavailable")
    end
    return true
end

function Lan.stop()
    if Lan.Active then
        Queue.publish(Protocol.encode_bye(Lan.Role, Queue.Seq))
    end
    Lan.Active = false
    Status.Lan = "Off"
    Status.set("Offline", "LAN stopped")
end

function Lan.debug_dump()
    local mode = refresh_role()
    Util.log(
        "LAN active=%s role=%s peer=%s sent=%d applied=%d mode=%s enable=%s fow=%s",
        tostring(Lan.Active), Lan.Role, tostring(Lan.PeerSeen),
        Lan.Sent, Lan.Applied, tostring(mode),
        tostring(Config.EnableLanSync), tostring(FoW.Viable)
    )
    return mode
end

return Lan
