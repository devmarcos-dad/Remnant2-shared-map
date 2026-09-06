local Util = require("lib.util")
local Status = require("lib.status")
local Probe = require("probe")
local Config = require("config")

--- Remnant 2 FoW viability layer.
--- Targets live Gunfire/Remnant minimap objects discovered in-game:
---   ExplorableMinimapManager / ExplorableMinimapModel(Remnant)
---   RemnantPlayerController:ClientUpdateFogOfWar
---   RemnantCheatManager:ToggleFogOfWar
local FoW = {
    Viable = false,
    LastError = nil,
    BoundObject = nil,
    BoundRevealFn = nil,
    BoundReadProp = nil,
    BoundModel = nil,
    BoundManager = nil,
    AppliedTiles = {},
    LastStrategy = nil,
}

local function is_usable_instance(obj)
    if not Util.is_valid(obj) then
        return false
    end
    local class_name = Util.safe_class_name(obj)
    local lower_class = Util.lower(class_name)
    for _, bad in ipairs(Config.RejectClassNames or {}) do
        if lower_class == Util.lower(bad) then
            return false
        end
    end
    local full = Util.lower(Util.safe_name(obj))
    if string.find(full, "default__", 1, true) then
        return false
    end
    -- Never treat a Function meta-object as a live gameplay instance.
    if string.find(full, "function ", 1, true) or lower_class == "function" then
        return false
    end
    return true
end

local function find_first(class_name)
    local ok, all = pcall(function() return FindAllOf(class_name) end)
    if ok and all then
        for _, candidate in pairs(all) do
            if is_usable_instance(candidate) then
                return candidate
            end
        end
    end
    local obj = nil
    pcall(function()
        obj = FindFirstOf(class_name)
    end)
    if is_usable_instance(obj) then
        return obj
    end
    return nil
end

local function call_method(obj, method_name, ...)
    if not Util.is_valid(obj) then
        return false, "invalid-object"
    end
    local args = { ... }
    local n = select("#", ...)
    local ok, err = pcall(function()
        local fn = obj[method_name]
        if fn == nil then
            error("missing-method:" .. tostring(method_name))
        end
        -- UE4SS: colon-call equivalent. Avoid calling meta Function UObjects.
        if n == 0 then
            return obj[method_name](obj)
        elseif n == 1 then
            return obj[method_name](obj, args[1])
        elseif n == 2 then
            return obj[method_name](obj, args[1], args[2])
        elseif n == 3 then
            return obj[method_name](obj, args[1], args[2], args[3])
        end
        return obj[method_name](obj, args[1], args[2], args[3], args[4])
    end)
    if ok then
        return true, nil
    end
    return false, tostring(err)
end

local function snapshot(obj, prop_name)
    if not prop_name or not Util.is_valid(obj) then
        return nil
    end
    local ok, value = pcall(function() return obj[prop_name] end)
    if not ok or value == nil then
        return nil
    end
    local t = Util.ue_type(value)
    if t == "number" or t == "boolean" or t == "string" then
        return tostring(value)
    end
    local ok_len, len = pcall(function() return #value end)
    if ok_len and type(len) == "number" then
        return string.format("%s#=%d", t, len)
    end
    local ok_name, name = pcall(function() return value:GetFullName() end)
    if ok_name and name then
        return name
    end
    return tostring(t)
end

local function resolve_manager_and_model()
    local manager = find_first("ExplorableMinimapManager")
    local model = find_first("ExplorableMinimapModelRemnant")
        or find_first("ExplorableMinimapModel")

    if Util.is_valid(manager) then
        local ok, maybe_model = pcall(function()
            if manager.GetExplorableMinimapModel ~= nil then
                return manager:GetExplorableMinimapModel()
            end
            return manager.ExplorableMinimapModel
        end)
        if ok and Util.is_valid(maybe_model) then
            model = maybe_model
        end
    end

    return manager, model
end

local function try_toggle_fog_cheat()
    local cheat = find_first("RemnantCheatManager")
    if not Util.is_valid(cheat) then
        -- Sometimes nested under player controller.
        local pc = find_first("RemnantPlayerController") or find_first("Remnant_PlayerController_C")
        if Util.is_valid(pc) then
            pcall(function()
                cheat = pc.CheatManager
            end)
        end
    end
    if not Util.is_valid(cheat) then
        return false, "no-cheat-manager"
    end
    local ok, err = call_method(cheat, "ToggleFogOfWar")
    if ok then
        FoW.BoundObject = cheat
        FoW.BoundRevealFn = "ToggleFogOfWar"
        FoW.LastStrategy = "RemnantCheatManager:ToggleFogOfWar"
        return true, "cheat-toggle"
    end
    return false, err
end

local function try_enable_fog_manager(manager)
    if not Util.is_valid(manager) then
        return false, "no-manager"
    end

    -- Read current state when possible.
    local before = nil
    pcall(function()
        if manager.IsFogOfWarEnabled ~= nil then
            before = tostring(manager:IsFogOfWarEnabled())
        end
    end)

    -- Force FoW on, then off, then on — visual flicker proves control.
    local ok1 = select(1, call_method(manager, "EnableFogOfWar", true))
    local ok2 = select(1, call_method(manager, "EnableFogOfWar", false))
    local ok3 = select(1, call_method(manager, "EnableFogOfWar", true))

    local after = nil
    pcall(function()
        if manager.IsFogOfWarEnabled ~= nil then
            after = tostring(manager:IsFogOfWarEnabled())
        end
    end)

    if ok1 or ok2 or ok3 then
        FoW.BoundObject = manager
        FoW.BoundRevealFn = "EnableFogOfWar"
        FoW.BoundManager = manager
        FoW.LastStrategy = string.format("manager EnableFogOfWar before=%s after=%s", tostring(before), tostring(after))
        return true, FoW.LastStrategy
    end
    return false, "EnableFogOfWar-failed"
end

local function try_reveal_hidden_area(model)
    if not Util.is_valid(model) then
        return false, "no-model"
    end

    local before = snapshot(model, "VisitedCoordinatesOwner")
        or snapshot(model, "TileBounds")
        or snapshot(model, "TileBoundsOrigin")

    -- Signature unknown; try common patterns.
    local attempts = {
        function() return model:RevealHiddenArea(0) end,
        function() return model:RevealHiddenArea(1) end,
        function() return model:RevealHiddenArea(0, true) end,
        function() return model:RevealHiddenArea(true) end,
        function() return model:RevealHiddenArea() end,
    }
    local succeeded = false
    local last_err = nil
    for _, call in ipairs(attempts) do
        local ok, err = pcall(call)
        if ok then
            succeeded = true
            break
        end
        last_err = tostring(err)
    end
    if not succeeded then
        return false, last_err or "RevealHiddenArea-failed"
    end

    local after = snapshot(model, "VisitedCoordinatesOwner")
        or snapshot(model, "TileBounds")
        or snapshot(model, "TileBoundsOrigin")

    FoW.BoundObject = model
    FoW.BoundModel = model
    FoW.BoundRevealFn = "RevealHiddenArea"
    FoW.LastStrategy = "model RevealHiddenArea"
    if before ~= nil and after ~= nil and before ~= after then
        return true, "property-changed"
    end
    return true, "call-ok"
end

local function try_bump_reveal_range()
    local comp = find_first("ExplorableMinimapComponent")
    if not Util.is_valid(comp) then
        return false, "no-component"
    end
    local before = snapshot(comp, "RevealRange")
    local ok, err = pcall(function()
        local current = comp.RevealRange or 0
        comp.RevealRange = math.max(tonumber(current) or 0, 5000)
        if comp.RevealRangeZ ~= nil then
            comp.RevealRangeZ = math.max(tonumber(comp.RevealRangeZ) or 0, 5000)
        end
    end)
    if not ok then
        return false, tostring(err)
    end
    local after = snapshot(comp, "RevealRange")
    FoW.BoundObject = comp
    FoW.BoundRevealFn = "RevealRange"
    FoW.LastStrategy = string.format("component RevealRange %s -> %s", tostring(before), tostring(after))
    if before ~= after then
        return true, "property-changed"
    end
    return true, "call-ok"
end

local function try_client_update_fog()
    local pc = find_first("RemnantPlayerController") or find_first("Remnant_PlayerController_C")
    if not Util.is_valid(pc) then
        return false, "no-player-controller"
    end
    -- Without a real visited-coordinates payload this may no-op, but a successful call
    -- still proves the API is reachable on the client path.
    local ok, err = call_method(pc, "ClientUpdateFogOfWar", nil)
    if not ok then
        ok, err = call_method(pc, "ClientUpdateFogOfWar")
    end
    if ok then
        FoW.BoundObject = pc
        FoW.BoundRevealFn = "ClientUpdateFogOfWar"
        FoW.LastStrategy = "RemnantPlayerController:ClientUpdateFogOfWar"
        return true, "call-ok"
    end
    return false, err
end

function FoW.read_revealed_tiles()
    if Util.is_valid(FoW.BoundModel) then
        local ok, value = pcall(function()
            return FoW.BoundModel.VisitedCoordinatesOwner or FoW.BoundModel.TileBounds
        end)
        if ok then return value, nil end
    end
    if Util.is_valid(FoW.BoundObject) and FoW.BoundReadProp then
        local ok, value = pcall(function()
            return FoW.BoundObject[FoW.BoundReadProp]
        end)
        if ok then return value, nil end
        return nil, tostring(value)
    end
    return nil, "no-bound-read"
end

function FoW.reveal_tile(zone_id, x, y)
    Status.RevealAttempts = (Status.RevealAttempts or 0) + 1
    -- Prefer model/manager strategies already validated.
    if FoW.BoundRevealFn == "RevealHiddenArea" and Util.is_valid(FoW.BoundModel) then
        local ok, detail = try_reveal_hidden_area(FoW.BoundModel)
        if ok then
            Status.RevealSuccesses = (Status.RevealSuccesses or 0) + 1
            FoW.AppliedTiles[string.format("%s:%s:%s", tostring(zone_id), tostring(x), tostring(y))] = true
        end
        return ok, detail
    end
    if FoW.BoundRevealFn == "EnableFogOfWar" and Util.is_valid(FoW.BoundManager) then
        local ok, detail = try_enable_fog_manager(FoW.BoundManager)
        if ok then
            Status.RevealSuccesses = (Status.RevealSuccesses or 0) + 1
        end
        return ok, detail
    end
    if Util.is_valid(FoW.BoundObject) and FoW.BoundRevealFn then
        local ok, err = call_method(FoW.BoundObject, FoW.BoundRevealFn, zone_id or 0, x or 0, y or 0)
        if not ok then
            ok, err = call_method(FoW.BoundObject, FoW.BoundRevealFn)
        end
        if ok then
            Status.RevealSuccesses = (Status.RevealSuccesses or 0) + 1
            return true, "call-ok"
        end
        FoW.LastError = err
        return false, err
    end
    return false, "no-bound-reveal"
end

function FoW.run_viability_probe()
    Status.set("Probing", "resolving Remnant minimap")
    Status.print_screen(3.0)

    -- Keep dump for diagnostics, but binding is now Remnant-specific.
    local candidates = {}
    pcall(function()
        candidates = Probe.run_dump() or {}
    end)
    Status.CandidateCount = #candidates

    local manager, model = resolve_manager_and_model()
    FoW.BoundManager = manager
    FoW.BoundModel = model

    Util.log(
        "resolve manager=%s model=%s",
        Util.safe_name(manager),
        Util.safe_name(model)
    )

    local attempts = {
        function() return try_enable_fog_manager(manager) end,
        function() return try_reveal_hidden_area(model) end,
        function() return try_bump_reveal_range() end,
        function() return try_toggle_fog_cheat() end,
        function() return try_client_update_fog() end,
    }

    local reveal_ok = false
    local reveal_detail = nil
    for _, attempt in ipairs(attempts) do
        local ok, detail = attempt()
        Util.log("strategy result ok=%s detail=%s", tostring(ok), tostring(detail))
        if ok then
            reveal_ok = true
            reveal_detail = detail
            break
        end
        FoW.LastError = detail
    end

    if reveal_ok then
        FoW.Viable = true
        Status.FoWViable = true
        Status.set("FoW OK", tostring(FoW.BoundRevealFn or FoW.LastStrategy))
        Status.print_screen(6.0)
        Util.log("VIABILITY=GO strategy=%s detail=%s", tostring(FoW.LastStrategy), tostring(reveal_detail))
        Util.log("%s", "Look at the minimap now. If fog toggled/tiles changed => confirmed GO.")
        return true, reveal_detail
    end

    FoW.Viable = false
    Status.FoWViable = false
    local why = FoW.LastError or "all-strategies-failed"
    Status.set("FoW FAIL", why)
    Status.print_screen(6.0)
    Util.log("VIABILITY=NO-GO reason=%s dump=%s", why, tostring(Probe.LastDumpPath))
    return false, why
end

function FoW.is_ready_for_lan()
    return FoW.Viable == true and Config.EnableLanSync == true
end

return FoW
