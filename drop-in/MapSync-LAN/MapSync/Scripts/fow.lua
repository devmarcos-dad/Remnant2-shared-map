--[[
  FoW: Remnant 2 ExplorableMinimap read/write for LAN sync.
  Apply order: ClientUpdateFogOfWar -> visited write -> RevealHiddenArea.
  Never treat EnableFogOfWar(false) as tile-reveal success.
]]

local Config = require("config")
local Util = require("lib.util")
local Status = require("lib.status")
local Probe = require("probe")

local FoW = {
    Viable = false,
    LastError = nil,
    LastStrategy = nil,
    BoundObject = nil,
    BoundRevealFn = nil,
    BoundModel = nil,
    BoundManager = nil,
    AppliedTiles = {},

    manager = nil,
    model = nil,
    component = nil,
    player_controller = nil,
    fog_enabled = nil,
    last_dump = nil,
    last_collect_reason = "not-yet",
    last_apply_ok = 0,
    last_apply_fail = 0,
    last_apply_method = nil,
    last_error = nil,
}

local TAG = "FoW"
local MAX_COLLECT = 400

local function log(fmt, ...)
    Util.flog(TAG, fmt, ...)
end

local function warn(...)
    Util.warn("[MapSync][FoW]", ...)
end

local function safe_call(label, fn)
    local ok, a = pcall(fn)
    if not ok then
        FoW.last_error = tostring(a)
        FoW.LastError = FoW.last_error
        log("ERR %s %s", label, tostring(a))
        return false, a
    end
    return true, a
end

local function is_uobject(obj)
    return obj ~= nil and type(obj) == "userdata"
end

local function obj_name(obj)
    return Util.safe_name(obj)
end

local function is_function_uobject(obj)
    local n = obj_name(obj)
    return type(n) == "string" and n:find("^Function ") ~= nil
end

local function is_usable_instance(obj)
    if not Util.is_valid(obj) then return false end
    if is_function_uobject(obj) then return false end
    local class_name = Util.safe_class_name(obj)
    local lower_class = Util.lower(class_name)
    for _, bad in ipairs(Config.RejectClassNames or {}) do
        if lower_class == Util.lower(bad) then return false end
    end
    local full = Util.lower(obj_name(obj))
    if string.find(full, "default__", 1, true) then return false end
    return true
end

local function find_first(class_name)
    local ok, all = pcall(function() return FindAllOf(class_name) end)
    if ok and all then
        local fallback = nil
        for _, candidate in pairs(all) do
            if is_usable_instance(candidate) then
                local full = Util.lower(obj_name(candidate))
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

local function get_local_pc()
    local ok, pcs = pcall(FindAllOf, "PlayerController")
    if ok and pcs then
        for _, pc in pairs(pcs) do
            if is_usable_instance(pc) then
                local local_ok = false
                pcall(function()
                    local_ok = pc.Pawn ~= nil and pc.Pawn:IsValid()
                end)
                if local_ok then return pc end
            end
        end
    end
    return find_first("RemnantPlayerController")
        or find_first("Remnant_PlayerController_C")
        or find_first("PlayerController")
end

local function container_num(c)
    if c == nil then return nil end
    local n
    pcall(function()
        if type(c.Num) == "function" then
            n = c:Num()
        elseif type(c.GetArrayNum) == "function" then
            n = c:GetArrayNum()
        else
            n = #c
        end
    end)
    if type(n) == "number" then return n end
    return nil
end

local function describe_shape(label, c)
    if c == nil then return string.format("%s=nil", label) end
    local t = type(c)
    local n = container_num(c)
    local sample = {}
    local count = 0
    pcall(function()
        if type(c.ForEach) == "function" then
            c:ForEach(function(key, value)
                if count >= 3 then return end
                count = count + 1
                table.insert(sample, string.format("%s=%s", tostring(key), tostring(value)))
            end)
        elseif n and n > 0 and type(c.Get) == "function" then
            for i = 1, math.min(3, n) do
                local ok, v = pcall(function() return c:Get(i - 1) end)
                if ok then
                    table.insert(sample, string.format("[%d]=%s", i - 1, tostring(v)))
                end
            end
        end
    end)
    return string.format("%s type=%s Num=%s sample={%s}", label, t, tostring(n), table.concat(sample, "; "))
end

local function push_xy(out, seen, x, y, zone)
    if type(x) ~= "number" or type(y) ~= "number" then return end
    if #out >= MAX_COLLECT then return end
    local xi, yi = math.floor(x + 0.5), math.floor(y + 0.5)
    local z = tonumber(zone) or 0
    local key = z .. ":" .. xi .. ":" .. yi
    if seen[key] then return end
    seen[key] = true
    table.insert(out, { zone = z, x = xi, y = yi })
end

local function extract_xy_from_value(value, out, seen, zone)
    if value == nil then return end
    local t = type(value)
    if t == "table" or t == "userdata" then
        local x, y, z
        pcall(function()
            x = value.X or value.x or value.CoordX or value[1]
            y = value.Y or value.y or value.CoordY or value[2]
            z = value.ZoneID or value.zone or value.Zone or value.AreaID or zone
        end)
        push_xy(out, seen, x, y, z)
        pcall(function()
            if type(value.Get) == "function" then
                local a = value:Get(0)
                local b = value:Get(1)
                push_xy(out, seen, a, b, zone)
            end
        end)
    end
end

local function iterate_container(c, out, seen, as_keys)
    if c == nil then return 0 end
    local before = #out
    local used = false
    pcall(function()
        if type(c.ForEach) == "function" then
            used = true
            c:ForEach(function(key, value)
                if as_keys then
                    extract_xy_from_value(key, out, seen)
                    if type(key) == "number" and type(value) == "number" then
                        push_xy(out, seen, key, value)
                    end
                else
                    extract_xy_from_value(value, out, seen)
                    extract_xy_from_value(key, out, seen)
                end
            end)
        end
    end)
    if not used then
        local n = container_num(c)
        if n and n > 0 then
            for i = 0, n - 1 do
                local ok, v = pcall(function()
                    if type(c.Get) == "function" then return c:Get(i) end
                    return c[i]
                end)
                if ok and v ~= nil then extract_xy_from_value(v, out, seen) end
            end
        else
            pcall(function()
                for k, v in pairs(c) do
                    if as_keys then extract_xy_from_value(k, out, seen) end
                    extract_xy_from_value(v, out, seen)
                    if type(k) == "number" and type(v) == "number" then
                        push_xy(out, seen, k, v)
                    end
                end
            end)
        end
    end
    return #out - before
end

local function collect_from_object(obj, out, seen)
    if not is_uobject(obj) then return end
    iterate_container(obj.VisitedCoordinatesMap, out, seen, true)
    iterate_container(obj.VisitedCoordinatesOwner, out, seen, true)
    iterate_container(obj.RevealedHiddenAreasIDs, out, seen, false)
    iterate_container(obj.RevealedAreas, out, seen, false)
end

function FoW.dump_structure()
    local lines = {}
    table.insert(lines, "manager=" .. obj_name(FoW.manager) .. " valid=" .. tostring(is_uobject(FoW.manager)))
    table.insert(lines, "model=" .. obj_name(FoW.model) .. " valid=" .. tostring(is_uobject(FoW.model)))
    table.insert(lines, "component=" .. obj_name(FoW.component) .. " valid=" .. tostring(is_uobject(FoW.component)))
    table.insert(lines, "pc=" .. obj_name(FoW.player_controller) .. " valid=" .. tostring(is_uobject(FoW.player_controller)))
    for _, t in ipairs({
        { "manager", FoW.manager },
        { "model", FoW.model },
        { "pc", FoW.player_controller },
    }) do
        local label, obj = t[1], t[2]
        if is_uobject(obj) then
            table.insert(lines, describe_shape(label .. ".VisitedCoordinatesMap", obj.VisitedCoordinatesMap))
            table.insert(lines, describe_shape(label .. ".VisitedCoordinatesOwner", obj.VisitedCoordinatesOwner))
            table.insert(lines, describe_shape(label .. ".RevealedHiddenAreasIDs", obj.RevealedHiddenAreasIDs))
        end
    end
    FoW.last_dump = table.concat(lines, " | ")
    log("DUMP %s", FoW.last_dump)
    return FoW.last_dump
end

function FoW.bind()
    local mgr = find_first("ExplorableMinimapManager")
    FoW.manager = mgr
    FoW.BoundManager = mgr
    log("bind manager %s %s", obj_name(mgr), mgr and "ok" or "missing")

    local model = find_first("ExplorableMinimapModelRemnant") or find_first("ExplorableMinimapModel")
    if mgr then
        pcall(function()
            if mgr.GetExplorableMinimapModel ~= nil then
                local maybe = mgr:GetExplorableMinimapModel()
                if is_usable_instance(maybe) then model = maybe end
            elseif is_usable_instance(mgr.ExplorableMinimapModel) then
                model = mgr.ExplorableMinimapModel
            end
        end)
    end
    FoW.model = model
    FoW.BoundModel = model
    log("bind model %s %s", obj_name(model), model and "ok" or "missing")

    local comp = find_first("ExplorableMinimapComponent")
    FoW.component = comp
    log("bind component %s %s", obj_name(comp), comp and "ok" or "missing")

    local pc = get_local_pc()
    FoW.player_controller = pc
    log("bind pc %s %s", obj_name(pc), pc and "ok" or "missing")

    if FoW.manager then
        pcall(function()
            FoW.fog_enabled = FoW.manager.bFogOfWarEnabled
            if FoW.fog_enabled == nil and FoW.manager.IsFogOfWarEnabled ~= nil then
                FoW.fog_enabled = FoW.manager:IsFogOfWarEnabled()
            end
        end)
    end

    FoW.dump_structure()
    return FoW.manager ~= nil or FoW.model ~= nil or FoW.player_controller ~= nil
end

function FoW.ensure_bound()
    if Util.is_valid(FoW.BoundManager) or Util.is_valid(FoW.manager) then
        FoW.manager = FoW.manager or FoW.BoundManager
        FoW.model = FoW.model or FoW.BoundModel
        return true
    end
    return FoW.bind()
end

-- Zone / world transition: old UObjects die; clear caches and force a fresh bind.
function FoW.reset_for_new_world(reason)
    log("world reset reason=%s", tostring(reason or "?"))
    FoW.manager = nil
    FoW.model = nil
    FoW.component = nil
    FoW.player_controller = nil
    FoW.BoundManager = nil
    FoW.BoundModel = nil
    FoW.BoundObject = nil
    FoW.AppliedTiles = {}
    FoW.last_collect_reason = "world-reset"
    FoW.last_apply_method = nil
    FoW.last_error = nil
    local ok = FoW.bind()
    log("world reset bind=%s", tostring(ok))
    return ok
end

function FoW.is_bound()
    return (Util.is_valid(FoW.manager) or Util.is_valid(FoW.BoundManager)
        or Util.is_valid(FoW.model) or Util.is_valid(FoW.BoundModel)
        or Util.is_valid(FoW.player_controller))
end

function FoW.get_fog_enabled()
    if not FoW.ensure_bound() then return nil end
    local manager = FoW.manager or FoW.BoundManager
    if not manager then return nil end
    local v = nil
    pcall(function()
        if manager.IsFogOfWarEnabled ~= nil then
            v = manager:IsFogOfWarEnabled()
        elseif manager.bFogOfWarEnabled ~= nil then
            v = manager.bFogOfWarEnabled
        elseif manager.bEnableFogOfWar ~= nil then
            v = manager.bEnableFogOfWar
        end
    end)
    if v == nil then return nil end
    FoW.fog_enabled = (v == true or v == 1 or tostring(v) == "true")
    return FoW.fog_enabled
end

function FoW.set_fog_enabled(enabled)
    if not FoW.ensure_bound() then return false, "no-manager" end
    local manager = FoW.manager or FoW.BoundManager
    if not manager then return false, "no-manager" end
    local ok, err = safe_call("EnableFogOfWar", function()
        manager:EnableFogOfWar(enabled and true or false)
    end)
    if ok then
        FoW.fog_enabled = enabled and true or false
        log("EnableFogOfWar %s", tostring(enabled))
    end
    return ok, err
end

function FoW.apply_fog_state(enabled)
    return FoW.set_fog_enabled(enabled)
end

function FoW.collect_revealed_tiles()
    local out, seen = {}, {}
    local reasons = {}
    if not FoW.is_bound() then FoW.bind() end

    if FoW.player_controller then
        local n = 0
        n = n + iterate_container(FoW.player_controller.VisitedCoordinatesMap, out, seen, true)
        n = n + iterate_container(FoW.player_controller.VisitedCoordinatesOwner, out, seen, true)
        if n == 0 then table.insert(reasons, "pc-visited-empty") end
    else
        table.insert(reasons, "no-pc")
    end

    if FoW.model then
        local before = #out
        collect_from_object(FoW.model, out, seen)
        if #out == before then table.insert(reasons, "model-empty") end
    else
        table.insert(reasons, "no-model")
    end

    if FoW.manager then
        local before = #out
        collect_from_object(FoW.manager, out, seen)
        if #out == before then table.insert(reasons, "manager-empty") end
    else
        table.insert(reasons, "no-manager")
    end

    if #out == 0 then
        FoW.last_collect_reason = table.concat(reasons, ",")
        log("collect tiles=0 reason=%s", FoW.last_collect_reason)
    else
        FoW.last_collect_reason = "ok"
        log("collect tiles=%d", #out)
    end
    return out
end

function FoW.tile_fingerprint(tiles)
    local n = #(tiles or {})
    if n == 0 then return "0" end
    local a, b = tiles[1], tiles[n]
    return string.format(
        "%d:%d:%d:%d:%d:%d:%d",
        n,
        a.zone or 0, a.x or 0, a.y or 0,
        b.zone or 0, b.x or 0, b.y or 0
    )
end

local function try_client_update_fog(x, y)
    local pc = FoW.player_controller
    if not is_uobject(pc) then return false, "no-pc" end
    if pc.ClientUpdateFogOfWar == nil then return false, "no-ClientUpdateFogOfWar" end
    local attempts = {
        function() pc:ClientUpdateFogOfWar(x, y) end,
        function() pc:ClientUpdateFogOfWar({ X = x, Y = y }) end,
        function() pc:ClientUpdateFogOfWar(x, y, true) end,
        function() pc:ClientUpdateFogOfWar({ X = x, Y = y, Z = 0 }) end,
    }
    for i, fn in ipairs(attempts) do
        local ok, err = pcall(fn)
        if ok then return true, "ClientUpdateFogOfWar#" .. tostring(i) end
        FoW.last_error = tostring(err)
    end
    return false, "ClientUpdateFogOfWar-all-failed"
end

local function try_write_visited(x, y)
    for _, obj in ipairs({ FoW.player_controller, FoW.model, FoW.manager }) do
        if is_uobject(obj) then
            local map = obj.VisitedCoordinatesMap
            if map ~= nil then
                local wrote = false
                pcall(function()
                    if type(map.Add) == "function" then
                        map:Add({ X = x, Y = y }, true)
                        wrote = true
                    elseif type(map) == "table" then
                        map[x .. ":" .. y] = true
                        wrote = true
                    end
                end)
                if wrote then return true, "VisitedCoordinatesMap.write" end
            end
            local owner = obj.VisitedCoordinatesOwner
            if owner ~= nil then
                local wrote = false
                pcall(function()
                    if type(owner.Add) == "function" then
                        owner:Add({ X = x, Y = y }, 0)
                        wrote = true
                    end
                end)
                if wrote then return true, "VisitedCoordinatesOwner.write" end
            end
        end
    end
    return false, "visited-write-failed"
end

local function try_reveal_hidden_area_xy(x, y, zone_id)
    local model = FoW.model or FoW.BoundModel
    if not is_uobject(model) then return false, "no-RevealHiddenArea" end
    local attempts = {
        function() model:RevealHiddenArea(x, y) end,
        function() model:RevealHiddenArea({ X = x, Y = y }) end,
        function() model:RevealHiddenArea(zone_id or 0) end,
        function() model:RevealHiddenArea(zone_id or 0, true) end,
        function() model:RevealHiddenArea(zone_id or 0, x, y) end,
        function() model:RevealHiddenArea(x, y, 1) end,
        function() model:RevealHiddenArea({ X = x, Y = y, Z = 0 }) end,
    }
    for i, fn in ipairs(attempts) do
        local ok, err = pcall(fn)
        if ok then return true, "RevealHiddenArea#" .. tostring(i) end
        FoW.last_error = tostring(err)
    end
    return false, "RevealHiddenArea-all-failed"
end

local function try_reveal_range_visual(x, y, z)
    if not is_uobject(FoW.component) then return false, "no-RevealRange" end
    local r = tonumber(Config.RevealRangeRadius) or 1500
    local zz = z or 0
    local attempts = {
        function() FoW.component:RevealRange({ X = x, Y = y, Z = zz }, r) end,
        function() FoW.component:RevealRange(x, y, zz, r) end,
    }
    for i, fn in ipairs(attempts) do
        local ok, err = pcall(fn)
        if ok then return true, "RevealRange#" .. tostring(i) end
        FoW.last_error = tostring(err)
    end
    return false, "RevealRange-failed"
end

-- reveal_tile(x,y) or reveal_tile(zone,x,y). Never fog-off-as-success.
function FoW.reveal_tile(a, b, c)
    Status.RevealAttempts = (Status.RevealAttempts or 0) + 1
    if not FoW.is_bound() then FoW.bind() end

    local zone_id, x, y
    if c ~= nil then
        zone_id, x, y = a, b, c
    else
        zone_id, x, y = 0, a, b
    end
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    zone_id = tonumber(zone_id) or 0

    local key = string.format("%d:%d:%d", zone_id, x, y)
    if FoW.AppliedTiles[key] then return true, "already" end

    local methods = {}
    local ok, method

    ok, method = try_client_update_fog(x, y)
    if ok then
        table.insert(methods, method)
        local ok2, m2 = try_write_visited(x, y)
        if ok2 then table.insert(methods, m2) end
        local ok3, m3 = try_reveal_hidden_area_xy(x, y, zone_id)
        if ok3 then table.insert(methods, m3) end
        try_reveal_range_visual(x, y, 0)
        FoW.last_apply_method = table.concat(methods, "+")
        FoW.last_apply_ok = FoW.last_apply_ok + 1
        FoW.AppliedTiles[key] = true
        Status.RevealSuccesses = (Status.RevealSuccesses or 0) + 1
        if Config.VerboseFoWLogs then
            log("apply ok x=%d y=%d method=%s", x, y, FoW.last_apply_method)
        end
        return true, FoW.last_apply_method
    end

    ok, method = try_write_visited(x, y)
    if ok then
        table.insert(methods, method)
        local ok3, m3 = try_reveal_hidden_area_xy(x, y, zone_id)
        if ok3 then table.insert(methods, m3) end
        try_reveal_range_visual(x, y, 0)
        FoW.last_apply_method = table.concat(methods, "+")
        FoW.last_apply_ok = FoW.last_apply_ok + 1
        FoW.AppliedTiles[key] = true
        Status.RevealSuccesses = (Status.RevealSuccesses or 0) + 1
        log("apply ok x=%d y=%d method=%s", x, y, FoW.last_apply_method)
        return true, FoW.last_apply_method
    end

    ok, method = try_reveal_hidden_area_xy(x, y, zone_id)
    if ok then
        try_reveal_range_visual(x, y, 0)
        FoW.last_apply_method = method
        FoW.last_apply_ok = FoW.last_apply_ok + 1
        FoW.AppliedTiles[key] = true
        Status.RevealSuccesses = (Status.RevealSuccesses or 0) + 1
        log("apply ok x=%d y=%d method=%s", x, y, method)
        return true, method
    end

    FoW.last_apply_fail = FoW.last_apply_fail + 1
    FoW.last_apply_method = "FAIL"
    FoW.LastError = FoW.last_error or "all-apply-paths-failed"
    warn("apply FAIL", x, y, "last_error=", FoW.last_error)
    return false, FoW.LastError
end

function FoW.reveal_at_world_pos(x, y, z)
    if not FoW.is_bound() then FoW.bind() end
    local ok_r, method = try_reveal_range_visual(x, y, z)
    local ok_t, method2 = FoW.reveal_tile(0, math.floor(x + 0.5), math.floor(y + 0.5))
    if ok_r or ok_t then
        local m = (ok_r and tostring(method) or "") .. (ok_t and ("+" .. tostring(method2)) or "")
        log("POS apply x=%.1f y=%.1f z=%.1f method=%s", x, y, z or 0, m)
        return true, m
    end
    warn("POS apply FAIL", x, y, z, FoW.last_error)
    return false, FoW.last_error
end

function FoW.get_local_pawn_pos()
    local pc = FoW.player_controller or get_local_pc()
    if not pc then return nil end
    local x, y, z
    pcall(function()
        local pawn = pc.Pawn
        if pawn and pawn:IsValid() then
            local loc = pawn:K2_GetActorLocation()
            if loc then
                x, y, z = loc.X, loc.Y, loc.Z
            end
        end
    end)
    if type(x) == "number" then
        return { x = x, y = y, z = z or 0 }
    end
    return nil
end

local function restore_fog_later(manager, enabled)
    local hold = Config.FogOffHoldMs or 3000
    local function restore()
        if not Util.is_valid(manager) then return end
        pcall(function() manager:EnableFogOfWar(enabled) end)
        log("%s", "Fog restored after hold")
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
        log("%s", "No delay API — leaving fog OFF for inspection")
    end
end

local function try_enable_fog_manager(manager)
    if not Util.is_valid(manager) then return false, "no-manager" end
    local before = FoW.get_fog_enabled()
    local ok_off = select(1, FoW.set_fog_enabled(false))
    local mid = FoW.get_fog_enabled()
    local ok_on = select(1, FoW.set_fog_enabled(true))
    local ok_off2 = select(1, FoW.set_fog_enabled(false))
    local after = FoW.get_fog_enabled()
    if not (ok_off or ok_on or ok_off2) then return false, "EnableFogOfWar-failed" end

    FoW.BoundObject = manager
    FoW.BoundRevealFn = "EnableFogOfWar"
    FoW.BoundManager = manager
    FoW.LastStrategy = string.format(
        "manager EnableFogOfWar before=%s mid=%s after=%s (fog left OFF %dms)",
        tostring(before), tostring(mid), tostring(after), Config.FogOffHoldMs or 3000
    )
    log("%s", ">>> OPEN MINIMAP NOW — fog should clear for a few seconds <<<")
    Status.set("FoW OK", "LOOK AT MINIMAP — fog OFF")
    Status.print_screen(5.0)
    restore_fog_later(manager, true)
    return true, FoW.LastStrategy
end

local function try_reveal_hidden_area_probe(model)
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
    local ok, err = pcall(function() cheat:ToggleFogOfWar() end)
    if ok then
        FoW.BoundObject = cheat
        FoW.BoundRevealFn = "ToggleFogOfWar"
        FoW.LastStrategy = "RemnantCheatManager:ToggleFogOfWar"
        return true, "ok"
    end
    return false, tostring(err)
end

function FoW.run_viability_probe()
    Status.set("Probing", "resolving Remnant minimap")
    Status.print_screen(3.0)

    if Config.ProbeDumpOnF7 then
        pcall(function() Probe.run_dump() end)
    else
        log("%s", "Skipping heavy dump on F7 (use F6 if needed)")
    end

    FoW.bind()
    local manager, model = FoW.manager or FoW.BoundManager, FoW.model or FoW.BoundModel
    log("resolve manager=%s model=%s", obj_name(manager), obj_name(model))

    local attempts = {
        function() return try_enable_fog_manager(manager) end,
        function() return try_reveal_hidden_area_probe(model) end,
        function() return try_toggle_fog_cheat() end,
    }
    for _, attempt in ipairs(attempts) do
        local ok, detail = attempt()
        log("strategy ok=%s detail=%s", tostring(ok), tostring(detail))
        if ok then
            FoW.Viable = true
            Status.FoWViable = true
            Status.set("FoW OK", tostring(FoW.BoundRevealFn or FoW.LastStrategy))
            Status.print_screen(6.0)
            log("VIABILITY=GO strategy=%s", tostring(FoW.LastStrategy))
            return true, detail
        end
        FoW.LastError = detail
    end

    FoW.Viable = false
    Status.FoWViable = false
    local why = FoW.LastError or "all-strategies-failed"
    Status.set("FoW FAIL", why)
    Status.print_screen(6.0)
    log("VIABILITY=NO-GO reason=%s", why)
    return false, why
end

function FoW.is_ready_for_lan()
    return FoW.Viable == true and Config.EnableLanSync == true
end

function FoW.status_line()
    return string.format(
        "bound=%s fog=%s collect=%s apply_ok=%d apply_fail=%d method=%s err=%s viable=%s",
        tostring(FoW.is_bound()),
        tostring(FoW.fog_enabled),
        tostring(FoW.last_collect_reason),
        FoW.last_apply_ok,
        FoW.last_apply_fail,
        tostring(FoW.last_apply_method),
        tostring(FoW.last_error or FoW.LastError),
        tostring(FoW.Viable)
    )
end

return FoW
