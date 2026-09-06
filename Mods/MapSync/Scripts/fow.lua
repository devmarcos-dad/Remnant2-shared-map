local Util = require("lib.util")
local Status = require("lib.status")
local Probe = require("probe")
local Config = require("config")

local FoW = {
    Viable = false,
    LastError = nil,
    BoundObject = nil,
    BoundRevealFn = nil,
    BoundModel = nil,
    BoundManager = nil,
    AppliedTiles = {},
    LastStrategy = nil,
    LastFogEnabled = nil,
    LastStrategy = nil,
    LastFogEnabled = nil,
}

local function is_usable_instance(obj)
    if not Util.is_valid(obj) then return false end
    local class_name = Util.safe_class_name(obj)
    local lower_class = Util.lower(class_name)
    for _, bad in ipairs(Config.RejectClassNames or {}) do
        if lower_class == Util.lower(bad) then return false end
    end
    local full = Util.lower(Util.safe_name(obj))
    if string.find(full, "default__", 1, true) then return false end
    if string.find(full, "function ", 1, true) or lower_class == "function" then return false end
    return true
end

local function find_first(class_name)
    local ok, all = pcall(function() return FindAllOf(class_name) end)
    if ok and all then
        local fallback = nil
        for _, candidate in pairs(all) do
            if is_usable_instance(candidate) then
                local full = Util.lower(Util.safe_name(candidate))
                if not string.find(full, "mainmenu", 1, true) then
                    return candidate
                end
                fallback = fallback or candidate
            end
        end
        if fallback ~= nil then return fallback end
    end
    local obj = nil
    pcall(function() obj = FindFirstOf(class_name) end)
    if is_usable_instance(obj) then return obj end
    return nil
end

local function call_method(obj, method_name, ...)
    if not Util.is_valid(obj) then return false, "invalid-object" end
    local args = { ... }
    local n = select("#", ...)
    local ok, err = pcall(function()
        if obj[method_name] == nil then error("missing-method:" .. tostring(method_name)) end
        if n == 0 then return obj[method_name](obj)
        elseif n == 1 then return obj[method_name](obj, args[1])
        elseif n == 2 then return obj[method_name](obj, args[1], args[2])
        elseif n == 3 then return obj[method_name](obj, args[1], args[2], args[3])
        end
        return obj[method_name](obj, args[1], args[2], args[3], args[4])
    end)
    if ok then return true, nil end
    return false, tostring(err)
end

local function read_fog_enabled(manager)
    if not Util.is_valid(manager) then return nil end
    local value = nil
    pcall(function()
        if manager.IsFogOfWarEnabled ~= nil then
            value = manager:IsFogOfWarEnabled()
        elseif manager.bEnableFogOfWar ~= nil then
            value = manager.bEnableFogOfWar
        end
    end)
    if value == nil then return nil end
    return value == true or value == 1 or tostring(value) == "true"
end

function FoW.ensure_bound()
    if Util.is_valid(FoW.BoundManager) then return true end
    local manager = find_first("ExplorableMinimapManager")
    local model = find_first("ExplorableMinimapModelRemnant") or find_first("ExplorableMinimapModel")
    if Util.is_valid(manager) then
        local ok, maybe = pcall(function()
            if manager.GetExplorableMinimapModel ~= nil then
                return manager:GetExplorableMinimapModel()
            end
            return manager.ExplorableMinimapModel
        end)
        if ok and Util.is_valid(maybe) then model = maybe end
    end
    FoW.BoundManager = manager
    FoW.BoundModel = model
    return Util.is_valid(manager)
end

function FoW.get_fog_enabled()
    if not FoW.ensure_bound() then return nil end
    return read_fog_enabled(FoW.BoundManager)
end

function FoW.set_fog_enabled(enabled)
    if not FoW.ensure_bound() then return false, "no-manager" end
    local ok = select(1, call_method(FoW.BoundManager, "EnableFogOfWar", enabled and true or false))
    if ok then
        FoW.LastFogEnabled = enabled and true or false
        return true, "ok"
    end
    return false, "EnableFogOfWar-failed"
end

function FoW.apply_fog_state(enabled)
    return FoW.set_fog_enabled(enabled)
end

local function push_tile(tiles, seen, zone, x, y)
    zone = tonumber(zone) or 0
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    local key = string.format("%d:%d:%d", zone, x, y)
    if seen[key] then return end
    seen[key] = true
    table.insert(tiles, { zone = zone, x = x, y = y })
end

local function collect_from_value(value, tiles, seen, depth)
    depth = depth or 0
    if depth > 3 or value == nil then return end
    local t = type(value)
    if t ~= "table" and t ~= "userdata" then return end
    local zx = value.ZoneID or value.zone or value.Zone or value.AreaID
    local x = value.X or value.x or value.CoordX
    local y = value.Y or value.y or value.CoordY
    if x ~= nil and y ~= nil then
        push_tile(tiles, seen, zx or 0, x, y)
    end
    pcall(function()
        if value.ForEach ~= nil then
            value:ForEach(function(k, v)
                if type(v) == "table" or type(v) == "userdata" then
                    collect_from_value(v, tiles, seen, depth + 1)
                elseif type(k) == "table" or type(k) == "userdata" then
                    collect_from_value(k, tiles, seen, depth + 1)
                end
            end)
        end
    end)
    pcall(function()
        for k, v in pairs(value) do
            if type(v) == "table" or type(v) == "userdata" then
                collect_from_value(v, tiles, seen, depth + 1)
            elseif type(k) == "table" or type(k) == "userdata" then
                collect_from_value(k, tiles, seen, depth + 1)
            elseif type(v) == "number" and type(k) == "number" then
                push_tile(tiles, seen, v, 0, 0)
            end
        end
    end)
end

function FoW.collect_revealed_tiles()
    FoW.ensure_bound()
    local tiles, seen = {}, {}
    local function try_prop(obj, name)
        if not Util.is_valid(obj) then return end
        local ok, value = pcall(function() return obj[name] end)
        if ok and value ~= nil then collect_from_value(value, tiles, seen, 0) end
    end
    try_prop(FoW.BoundModel, "VisitedCoordinatesOwner")
    try_prop(FoW.BoundModel, "VisitedCoordinatesMap")
    try_prop(FoW.BoundModel, "RevealedHiddenAreasIDs")
    try_prop(FoW.BoundManager, "VisitedCoordinatesOwner")
    try_prop(FoW.BoundManager, "VisitedCoordinatesMap")
    try_prop(FoW.BoundManager, "RevealedHiddenAreasIDs")
    local pc = find_first("RemnantPlayerController") or find_first("Remnant_PlayerController_C")
    try_prop(pc, "VisitedCoordinatesMap")
    Util.log("collect_tiles count=%d", #tiles)
    return tiles
end

function FoW.tile_fingerprint(tiles)
    local n = #(tiles or {})
    if n == 0 then return "0" end
    local a, b = tiles[1], tiles[n]
    return string.format("%d:%d:%d:%d:%d:%d:%d", n, a.zone, a.x, a.y, b.zone, b.x, b.y)
end

function FoW.reveal_tile(zone_id, x, y)
    Status.RevealAttempts = (Status.RevealAttempts or 0) + 1
    FoW.ensure_bound()
    local key = string.format("%s:%s:%s", tostring(zone_id), tostring(x), tostring(y))
    if FoW.AppliedTiles[key] then return true, "already" end

    if Util.is_valid(FoW.BoundModel) then
        local attempts = {
            function() return FoW.BoundModel:RevealHiddenArea(zone_id) end,
            function() return FoW.BoundModel:RevealHiddenArea(zone_id, true) end,
            function() return FoW.BoundModel:RevealHiddenArea(x, y) end,
            function() return FoW.BoundModel:RevealHiddenArea(zone_id, x, y) end,
        }
        for _, call in ipairs(attempts) do
            if pcall(call) then
                FoW.AppliedTiles[key] = true
                Status.RevealSuccesses = (Status.RevealSuccesses or 0) + 1
                FoW.BoundRevealFn = "RevealHiddenArea"
                return true, "RevealHiddenArea"
            end
        end
    end

    local ok = select(1, FoW.set_fog_enabled(false))
    if ok then
        FoW.AppliedTiles[key] = true
        Status.RevealSuccesses = (Status.RevealSuccesses or 0) + 1
        return true, "fog-off-fallback"
    end
    return false, "reveal-failed"
end

local function restore_fog_later(manager, enabled)
    local hold = Config.FogOffHoldMs or 3000
    local function restore()
        if not Util.is_valid(manager) then return end
        call_method(manager, "EnableFogOfWar", enabled)
        Util.log("%s", "Fog restored after hold")
        Status.set("FoW OK", "fog restored")
        Status.print_screen(4.0)
    end
    if ExecuteWithDelay ~= nil then
        ExecuteWithDelay(hold, restore)
    elseif LoopAsync ~= nil then
        local done = false
        LoopAsync(hold, function()
            if done then return true end
            done = true
            restore()
            return true
        end)
    else
        Util.log("%s", "No delay API — leaving fog OFF for inspection")
    end
end

local function try_enable_fog_manager(manager)
    if not Util.is_valid(manager) then return false, "no-manager" end
    local before = read_fog_enabled(manager)
    local ok_off = select(1, call_method(manager, "EnableFogOfWar", false))
    local mid = read_fog_enabled(manager)
    local ok_on = select(1, call_method(manager, "EnableFogOfWar", true))
    local ok_off2 = select(1, call_method(manager, "EnableFogOfWar", false))
    local after = read_fog_enabled(manager)
    if not (ok_off or ok_on or ok_off2) then return false, "EnableFogOfWar-failed" end

    FoW.BoundObject = manager
    FoW.BoundRevealFn = "EnableFogOfWar"
    FoW.BoundManager = manager
    FoW.LastStrategy = string.format(
        "manager EnableFogOfWar before=%s mid=%s after=%s (fog left OFF %dms)",
        tostring(before), tostring(mid), tostring(after), Config.FogOffHoldMs or 3000
    )
    Util.log("%s", ">>> OPEN MINIMAP NOW — fog should be cleared for a few seconds <<<")
    Status.set("FoW OK", "LOOK AT MINIMAP — fog OFF")
    Status.print_screen(5.0)
    restore_fog_later(manager, true)
    return true, FoW.LastStrategy
end

local function try_reveal_hidden_area(model)
    if not Util.is_valid(model) then return false, "no-model" end
    local attempts = {
        function() return model:RevealHiddenArea(0) end,
        function() return model:RevealHiddenArea(1) end,
        function() return model:RevealHiddenArea(0, true) end,
        function() return model:RevealHiddenArea() end,
    }
    for _, call in ipairs(attempts) do
        if pcall(call) then
            FoW.BoundObject = model
            FoW.BoundModel = model
            FoW.BoundRevealFn = "RevealHiddenArea"
            FoW.LastStrategy = "model RevealHiddenArea"
            return true, "ok"
        end
    end
    return false, "RevealHiddenArea-failed"
end

local function try_toggle_fog_cheat()
    local cheat = find_first("RemnantCheatManager")
    if not Util.is_valid(cheat) then
        local pc = find_first("RemnantPlayerController") or find_first("Remnant_PlayerController_C")
        if Util.is_valid(pc) then pcall(function() cheat = pc.CheatManager end) end
    end
    if not Util.is_valid(cheat) then return false, "no-cheat" end
    local ok, err = call_method(cheat, "ToggleFogOfWar")
    if ok then
        FoW.BoundObject = cheat
        FoW.BoundRevealFn = "ToggleFogOfWar"
        FoW.LastStrategy = "RemnantCheatManager:ToggleFogOfWar"
        return true, "ok"
    end
    return false, err
end

function FoW.run_viability_probe()
    Status.set("Probing", "resolving Remnant minimap")
    Status.print_screen(3.0)

    if Config.ProbeDumpOnF7 then
        pcall(function() Probe.run_dump() end)
    else
        Util.log("%s", "Skipping heavy dump on F7 (use F6 if needed)")
    end

    FoW.ensure_bound()
    local manager, model = FoW.BoundManager, FoW.BoundModel
    Util.log("resolve manager=%s model=%s", Util.safe_name(manager), Util.safe_name(model))

    local attempts = {
        function() return try_enable_fog_manager(manager) end,
        function() return try_reveal_hidden_area(model) end,
        function() return try_toggle_fog_cheat() end,
    }
    for _, attempt in ipairs(attempts) do
        local ok, detail = attempt()
        Util.log("strategy ok=%s detail=%s", tostring(ok), tostring(detail))
        if ok then
            FoW.Viable = true
            Status.FoWViable = true
            Status.set("FoW OK", tostring(FoW.BoundRevealFn or FoW.LastStrategy))
            Status.print_screen(6.0)
            Util.log("VIABILITY=GO strategy=%s", tostring(FoW.LastStrategy))
            return true, detail
        end
        FoW.LastError = detail
    end

    FoW.Viable = false
    Status.FoWViable = false
    local why = FoW.LastError or "all-strategies-failed"
    Status.set("FoW FAIL", why)
    Status.print_screen(6.0)
    Util.log("VIABILITY=NO-GO reason=%s", why)
    return false, why
end

function FoW.is_ready_for_lan()
    return FoW.Viable == true and Config.EnableLanSync == true
end

return FoW
