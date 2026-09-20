local Config = require("config")
local Util = require("lib.util")
local Status = require("lib.status")
local NetMode = require("lib.netmode")
local FoW = require("fow")
local Lan = require("net.lan")
local Probe = require("probe")
local Bridge = require("net.bridge")

Util.log("%s %s loading", Config.ModName or "MapSync", Config.Version or "?")
Status.set("Boot", Config.Version or "?", { force_log = true })
Status.start_refresh_loop(Config.StatusRefreshMs or 5000)

-- Warm the bridge early so F7 does not race peer discovery.
if Config.EnableLanSync and Config.AutoStartBridge ~= false then
    local ok, detail = Bridge.start()
    Util.flog("LAN", "boot bridge ok=%s detail=%s", tostring(ok), tostring(detail))
end

local function refresh_net_status()
    local mode = NetMode.detect()
    Status.NetMode = mode
    return mode
end

local function run_probe()
    refresh_net_status()
    local ok = FoW.run_viability_probe()
    if ok and Config.EnableLanSync then
        Util.flog("LAN", "FoW GO — starting LAN role=%s", NetMode.role_label(NetMode.detect()))
        Lan.start()
    elseif ok then
        Util.log("%s", "FoW GO — set EnableLanSync=true in config.lua, then press F7 or F9")
    end
    return ok
end

local function bind_key(name, callback)
    local key = Util.resolve_key(name)
    if key == nil then
        Util.log("unknown key %s", tostring(name))
        return
    end
    if RegisterKeyBind == nil then
        Util.log("%s", "RegisterKeyBind unavailable")
        return
    end
    pcall(function() RegisterKeyBind(key, callback) end)
end

bind_key(Config.Keys.Dump, function()
    Util.log("%s", "F6: heavy reflection dump")
    local candidates = Probe.run_dump()
    Status.CandidateCount = #(candidates or {})
    Status.set("Probing", string.format("dump=%d", Status.CandidateCount))
    Status.print_screen(3.0)
end)

bind_key(Config.Keys.ProbeReveal, function()
    Util.log("%s", "F7: light viability / LAN arm")
    run_probe()
end)

bind_key(Config.Keys.ToggleStatus, function()
    Status.toggle()
    Status.print_screen(2.0)
end)

bind_key(Config.Keys.DumpNet, function()
    local mode = refresh_net_status()
    Util.flog(
        "LAN",
        "F9 role=%s active=%s peer=%s sent=%d applied=%d bridge=%s",
        NetMode.role_label(mode),
        tostring(Lan.Active),
        tostring(Lan.PeerSeen),
        Lan.Sent or 0,
        Lan.Applied or 0,
        tostring(Bridge.is_running())
    )
    if Config.EnableLanSync and FoW.Viable and not Lan.Active then
        Util.flog("LAN", "%s", "F9: starting LAN sync")
        Lan.start()
    end
    Lan.debug_dump()
end)

local auto_probe_scheduled = false
local function schedule_auto_probe(reason)
    if not Config.AutoProbeOnWorld or auto_probe_scheduled then return end
    auto_probe_scheduled = true
    local delay = Config.AutoProbeDelayMs or 5000
    Util.log("auto-probe scheduled (%s) in %dms", tostring(reason), delay)
    local function fire()
        refresh_net_status()
        Status.set("Probing", "auto:" .. tostring(reason))
        run_probe()
    end
    if ExecuteWithDelay ~= nil then
        ExecuteWithDelay(delay, fire)
    elseif LoopAsync ~= nil then
        local fired = false
        LoopAsync(delay, function()
            if fired then return true end
            fired = true
            fire()
            return true
        end)
    else
        auto_probe_scheduled = false
    end
end

local rebind_generation = 0
local function schedule_world_rebind(reason)
    rebind_generation = rebind_generation + 1
    local gen = rebind_generation
    local delay = Config.WorldRebindDelayMs or 2500
    Util.flog("LAN", "schedule world rebind (%s) in %dms", tostring(reason), delay)
    local function fire()
        if gen ~= rebind_generation then return end
        refresh_net_status()
        Lan.on_world_changed(reason)
    end
    if ExecuteWithDelay ~= nil then
        ExecuteWithDelay(delay, fire)
    elseif LoopAsync ~= nil then
        local fired = false
        LoopAsync(delay, function()
            if fired then return true end
            fired = true
            fire()
            return true
        end)
    else
        fire()
    end
end

local function shutdown_bridge(reason)
    Util.flog("LAN", "shutdown bridge (%s)", tostring(reason))
    pcall(function() Lan.stop() end)
    pcall(function() Bridge.stop() end)
end

pcall(function()
    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
        Util.log("%s", "ClientRestart — world available")
        Status.set("World", "zone/world ready")
        schedule_auto_probe("ClientRestart")
        if FoW.Viable or Lan.Active then
            schedule_world_rebind("ClientRestart")
        elseif Config.EnableLanSync and FoW.Viable and not Lan.Active then
            FoW.ensure_bound()
            Lan.start()
        end
    end)
end)

-- Best-effort exit hooks so the bridge does not keep running after Remnant quits.
pcall(function()
    RegisterHook("/Script/Engine.GameEngine:Close", function()
        shutdown_bridge("GameEngine:Close")
    end)
end)
pcall(function()
    RegisterHook("/Script/Engine.GameViewportClient:HandleExitCommand", function()
        shutdown_bridge("HandleExitCommand")
    end)
end)
pcall(function()
    if type(NotifyOnUnrealExit) == "function" then
        NotifyOnUnrealExit(function()
            shutdown_bridge("NotifyOnUnrealExit")
        end)
    end
end)

Util.log("%s", "Ready. F6=dump | F7=FoW/LAN | F8=status | F9=LAN dump | bridge auto-start/kill")
