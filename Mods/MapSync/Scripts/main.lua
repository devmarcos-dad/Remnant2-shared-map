local Config = require("config")
local Util = require("lib.util")
local Status = require("lib.status")
local NetMode = require("lib.netmode")
local FoW = require("fow")
local Lan = require("net.lan")
local Probe = require("probe")

Util.log("%s %s loading", Config.ModName or "MapSync", Config.Version or "?")
Status.set("Boot", Config.Version or "?", { force_log = true })
Status.start_refresh_loop(Config.StatusRefreshMs or 5000)

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
        "F9 role=%s active=%s peer=%s sent=%d applied=%d",
        NetMode.role_label(mode),
        tostring(Lan.Active),
        tostring(Lan.PeerSeen),
        Lan.Sent or 0,
        Lan.Applied or 0
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

pcall(function()
    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
        Util.log("%s", "ClientRestart — world available")
        Status.set("World", "ready — open minimap and press F7")
        schedule_auto_probe("ClientRestart")
        if Config.EnableLanSync and FoW.Viable and not Lan.Active then
            FoW.ensure_bound()
            Lan.start()
        end
    end)
end)

Util.log("%s", "Ready. F6=heavy dump | F7=fog test/LAN arm | F8=status | F9=net/LAN dump")
