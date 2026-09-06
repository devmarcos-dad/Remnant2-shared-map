local Util = require("lib.util")
local Status = require("lib.status")
local Probe = require("probe")
local Config = require("config")

local FoW = {
    Viable = false,
    LastError = nil,
    BoundObject = nil,
    BoundRevealFn = nil,
    BoundReadProp = nil,
    AppliedTiles = {},
}

local REVEAL_NAMES = {
    "RevealTile", "RevealTiles", "RevealArea", "ExploreTile",
    "SetTileExplored", "ClearFog", "Unfog", "RevealMap",
    "DiscoverTile", "PaintTile", "RevealFogOfWar", "SetFogRevealed",
}

local READ_PROP_NAMES = {
    "RevealedTiles", "ExploredTiles", "FogMask", "ExplorationMask",
    "VisitedTiles", "DiscoveredAreas", "RevealedRegions", "MiniMapRevealMask",
}

local function snapshot_prop(obj, prop_name)
    local ok, value = pcall(function() return obj[prop_name] end)
    if not ok or value == nil then return nil end
    local t = Util.ue_type(value)
    if t == "number" or t == "boolean" or t == "string" then
        return tostring(value)
    end
    local ok_len, len = pcall(function() return #value end)
    if ok_len and type(len) == "number" then
        return string.format("%s#=%s", t, tostring(len))
    end
    return tostring(t)
end

local function try_call_reveal(obj, fn_name)
    local ok_get, got = pcall(function() return obj[fn_name] end)
    if not ok_get or got == nil then
        return false, "missing"
    end
    local attempts = {
        function() return obj[fn_name](obj) end,
        function() return obj[fn_name](obj, 0, 0) end,
        function() return obj[fn_name](obj, 0, 0, 0) end,
        function() return obj[fn_name](obj, 1, 1) end,
        function() return obj[fn_name](obj, 0) end,
        function() return obj[fn_name](obj, true) end,
    }
    for _, call in ipairs(attempts) do
        local ok, err = pcall(call)
        if ok then return true, fn_name end
        FoW.LastError = tostring(err)
    end
    return false, FoW.LastError or "call-failed"
end

local function pick_binding(candidates)
    for _, c in ipairs(candidates) do
        local obj = c.object
        if not Util.is_valid(obj) then goto continue end

        local reveal_fn = nil
        for _, f in ipairs(c.functions or {}) do
            local lower = Util.lower(f.name)
            for _, wanted in ipairs(REVEAL_NAMES) do
                if lower == Util.lower(wanted) then
                    reveal_fn = f.name
                    break
                end
            end
            if reveal_fn then break end
            if string.find(lower, "reveal", 1, true)
                or string.find(lower, "explore", 1, true)
                or string.find(lower, "unfog", 1, true) then
                reveal_fn = f.name
                break
            end
        end

        local read_prop = nil
        for _, p in ipairs(c.properties or {}) do
            local lower = Util.lower(p.name)
            for _, wanted in ipairs(READ_PROP_NAMES) do
                if lower == Util.lower(wanted) then
                    read_prop = p.name
                    break
                end
            end
            if read_prop then break end
            if string.find(lower, "reveal", 1, true)
                or string.find(lower, "explor", 1, true)
                or string.find(lower, "fog", 1, true) then
                read_prop = p.name
            end
        end

        if reveal_fn or read_prop or (c.score or 0) >= 3 then
            return obj, reveal_fn, read_prop, c
        end
        ::continue::
    end
    return nil, nil, nil, nil
end

function FoW.read_revealed_tiles()
    if not Util.is_valid(FoW.BoundObject) or not FoW.BoundReadProp then
        return nil, "no-bound-read-prop"
    end
    local ok, value = pcall(function()
        return FoW.BoundObject[FoW.BoundReadProp]
    end)
    if not ok then return nil, tostring(value) end
    return value, nil
end

function FoW.reveal_tile(zone_id, x, y)
    Status.RevealAttempts = Status.RevealAttempts + 1
    if not Util.is_valid(FoW.BoundObject) then
        return false, "no-bound-object"
    end
    if not FoW.BoundRevealFn then
        return false, "no-bound-reveal-fn"
    end

    local fn_name = FoW.BoundRevealFn
    local before = FoW.BoundReadProp and snapshot_prop(FoW.BoundObject, FoW.BoundReadProp) or nil
    local calls = {
        function() return FoW.BoundObject[fn_name](FoW.BoundObject, zone_id or 0, x or 0, y or 0) end,
        function() return FoW.BoundObject[fn_name](FoW.BoundObject, x or 0, y or 0) end,
        function() return FoW.BoundObject[fn_name](FoW.BoundObject, x or 0, y or 0, zone_id or 0) end,
        function() return FoW.BoundObject[fn_name](FoW.BoundObject) end,
    }

    local succeeded = false
    local last_err = nil
    for _, call in ipairs(calls) do
        local ok, err = pcall(call)
        if ok then
            succeeded = true
            break
        end
        last_err = tostring(err)
    end
    if not succeeded then
        FoW.LastError = last_err
        return false, last_err
    end

    local after = FoW.BoundReadProp and snapshot_prop(FoW.BoundObject, FoW.BoundReadProp) or nil
    Status.RevealSuccesses = Status.RevealSuccesses + 1
    FoW.AppliedTiles[string.format("%s:%s:%s", tostring(zone_id), tostring(x), tostring(y))] = true

    if before ~= nil and after ~= nil and before ~= after then
        Util.log("reveal_tile property changed %s -> %s", before, after)
        return true, "property-changed"
    end
    return true, "call-ok"
end

function FoW.run_viability_probe()
    Status.set("Probing", "dumping reflection")
    Status.print_screen(3.0)

    local candidates = Probe.run_dump()
    Status.CandidateCount = #candidates

    local obj, reveal_fn, read_prop, meta = pick_binding(candidates)
    FoW.BoundObject = obj
    FoW.BoundRevealFn = reveal_fn
    FoW.BoundReadProp = read_prop

    if not Util.is_valid(obj) then
        FoW.Viable = false
        Status.FoWViable = false
        Status.set("FoW FAIL", "no map/fog candidates")
        Status.print_screen(5.0)
        Util.log("%s", "VIABILITY=NO-GO reason=no-candidates")
        return false, "no-candidates"
    end

    Util.log(
        "bound class=%s reveal=%s read=%s score=%s",
        Util.safe_class_name(obj),
        tostring(reveal_fn),
        tostring(read_prop),
        tostring(meta and meta.score)
    )

    local reveal_ok = false
    local reveal_detail = nil
    if reveal_fn then
        reveal_ok, reveal_detail = try_call_reveal(obj, reveal_fn)
        if reveal_ok then FoW.BoundRevealFn = reveal_fn end
    else
        for _, name in ipairs(REVEAL_NAMES) do
            local ok, detail = try_call_reveal(obj, name)
            if ok then
                reveal_ok = true
                reveal_detail = detail
                FoW.BoundRevealFn = name
                break
            end
        end
    end

    if reveal_ok and FoW.BoundRevealFn then
        local ok2, detail2 = FoW.reveal_tile(0, 0, 0)
        reveal_ok = ok2
        reveal_detail = detail2
    end

    if reveal_ok then
        FoW.Viable = true
        Status.FoWViable = true
        Status.set("FoW OK", string.format("reveal=%s", tostring(FoW.BoundRevealFn)))
        Status.print_screen(5.0)
        Util.log("VIABILITY=GO reveal=%s detail=%s", tostring(FoW.BoundRevealFn), tostring(reveal_detail))
        Util.log("%s", "Confirm visually on the minimap. If tiles changed, enable LAN sync.")
        return true, reveal_detail
    end

    FoW.Viable = false
    Status.FoWViable = false
    local why = FoW.LastError or "reveal-failed"
    Status.set("FoW FAIL", why)
    Status.print_screen(5.0)
    Util.log("VIABILITY=NO-GO reason=%s dump=%s", why, tostring(Probe.LastDumpPath))
    return false, why
end

function FoW.is_ready_for_lan()
    return FoW.Viable == true and Config.EnableLanSync == true
end

return FoW
