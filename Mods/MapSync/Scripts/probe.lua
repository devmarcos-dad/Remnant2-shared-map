local Util = require("lib.util")
local Config = require("config")

local Probe = {
    LastCandidates = {},
    LastDumpPath = nil,
}

local function score_text(text, keywords)
    local score = 0
    local lower = Util.lower(text)
    for _, kw in ipairs(keywords) do
        if string.find(lower, Util.lower(kw), 1, true) then
            score = score + 1
        end
    end
    return score
end

local function is_rejected_class(class_name)
    local lower = Util.lower(class_name)
    for _, bad in ipairs(Config.RejectClassNames or {}) do
        if lower == Util.lower(bad) then
            return true
        end
    end
    -- Also reject default objects / CDO noise when possible.
    return false
end

local function is_live_instance(obj, full_name, class_name)
    if not Util.is_valid(obj) then
        return false
    end
    if is_rejected_class(class_name) then
        return false
    end
    local full = Util.lower(full_name or "")
    if string.find(full, "default__", 1, true) then
        return false
    end
    -- UE4SS often surfaces Function/Class meta objects with FogOfWar-ish names.
    if string.find(full, "function ", 1, true) or string.find(full, " class ", 1, true) then
        return false
    end
    if string.find(full, "/script/", 1, true) and not string.find(full, "persistentlevel", 1, true)
        and not string.find(full, "transient", 1, true) then
        -- Class/Function path style, not a world instance.
        if class_name == "Class" or class_name == "Function" then
            return false
        end
    end
    return true
end

local function collect_reflection(obj)
    local props = {}
    local funcs = {}

    pcall(function()
        if obj.ForEachProperty == nil then return end
        obj:ForEachProperty(function(prop)
            local name = nil
            pcall(function() name = prop:GetFName():ToString() end)
            if name and score_text(name, Config.PropertyKeywords) > 0 then
                table.insert(props, { name = name, score = score_text(name, Config.PropertyKeywords) })
            end
        end)
    end)

    pcall(function()
        if obj.ForEachFunction == nil then return end
        obj:ForEachFunction(function(fn)
            local name = nil
            pcall(function() name = fn:GetFName():ToString() end)
            if name and score_text(name, Config.FunctionKeywords) > 0 then
                table.insert(funcs, { name = name, score = score_text(name, Config.FunctionKeywords) })
            end
        end)
    end)

    -- Only probe known Remnant/Gunfire fields if iterators found nothing.
    if #props == 0 then
        for _, pname in ipairs({
            "ExplorableMinimapModel", "VisitedCoordinatesOwner", "VisitedCoordinatesMap",
            "RevealRange", "RevealRangeZ", "TileBounds", "TileBoundsOrigin",
            "RevealedHiddenAreasIDs", "MinimapStaticMeshList",
        }) do
            local ok, value = pcall(function() return obj[pname] end)
            if ok and value ~= nil then
                table.insert(props, { name = pname, score = 3, preview = Util.ue_type(value) })
            end
        end
    end

    if #funcs == 0 then
        for _, fname in ipairs({
            "EnableFogOfWar", "IsFogOfWarEnabled", "GetExplorableMinimapModel",
            "GetExplorableMinimapManager", "RevealHiddenArea", "GetVisibilityAtLocation",
            "ToggleFogOfWar", "ClientUpdateFogOfWar", "OnTileVisibilityUpdate",
        }) do
            local ok, fn = pcall(function() return obj[fname] end)
            if ok and fn ~= nil then
                table.insert(funcs, { name = fname, score = 3 })
            end
        end
    end

    table.sort(props, function(a, b) return a.score > b.score end)
    table.sort(funcs, function(a, b) return a.score > b.score end)
    return props, funcs
end

local function priority_bonus(class_name, full_name)
    local blob = Util.lower(class_name .. " " .. full_name)
    local bonus = 0
    for _, name in ipairs(Config.PriorityClassNames or {}) do
        if string.find(blob, Util.lower(name), 1, true) then
            bonus = bonus + 20
            break
        end
    end
    if string.find(blob, "explorableminimapmanager", 1, true) then
        bonus = bonus + 15
    end
    if string.find(blob, "explorableminimapmodel", 1, true) then
        bonus = bonus + 12
    end
    return bonus
end

local function add_candidate(bucket, obj, source, bonus)
    if not Util.is_valid(obj) then return end
    local full = Util.safe_name(obj)
    local class_name = Util.safe_class_name(obj)
    if not is_live_instance(obj, full, class_name) then
        return
    end
    if bucket._seen[full] then return end
    bucket._seen[full] = true

    local cscore = score_text(class_name .. " " .. full, Config.ClassKeywords)
    local props, funcs = collect_reflection(obj)
    local total = (bonus or 0) + cscore + priority_bonus(class_name, full)
        + math.min(4, #props) + math.min(4, #funcs)
    if total <= 0 and source ~= "priority" then return end

    table.insert(bucket, {
        source = source,
        full_name = full,
        class_name = class_name,
        score = total,
        properties = props,
        functions = funcs,
        object = obj,
    })
end

local function dump_priority_classes(bucket)
    for _, class_name in ipairs(Config.PriorityClassNames or {}) do
        local ok, instances = pcall(function() return FindAllOf(class_name) end)
        if ok and instances then
            local count = 0
            for _, obj in pairs(instances) do
                add_candidate(bucket, obj, "priority", 25)
                count = count + 1
            end
            Util.log("priority FindAllOf(%s) => %d", class_name, count)
        else
            local one = nil
            pcall(function() one = FindFirstOf(class_name) end)
            if Util.is_valid(one) then
                add_candidate(bucket, one, "priority", 25)
                Util.log("priority FindFirstOf(%s) => 1", class_name)
            else
                Util.log("priority miss %s", class_name)
            end
        end
    end
end

local function dump_uobject_scan(bucket)
    if ForEachUObject == nil then
        Util.log("%s", "ForEachUObject unavailable; skipping full scan")
        return
    end
    local scanned = 0
    local max_scan = Config.MaxUObjectScan or 25000
    pcall(function()
        ForEachUObject(function(obj)
            scanned = scanned + 1
            if scanned > max_scan then return end
            if not Util.is_valid(obj) then return end
            local class_name = Util.safe_class_name(obj)
            local full = Util.safe_name(obj)
            if not is_live_instance(obj, full, class_name) then return end
            local cscore = score_text(class_name .. " " .. full, Config.ClassKeywords)
            if cscore > 0 or priority_bonus(class_name, full) > 0 then
                add_candidate(bucket, obj, "scan", cscore)
            end
        end)
    end)
    Util.log("UObject scan finished scanned=%d candidates=%d", scanned, #bucket)
end

local function format_candidate(c)
    local prop_names, fn_names = {}, {}
    for i, p in ipairs(c.properties) do
        if i > 8 then break end
        table.insert(prop_names, p.name)
    end
    for i, f in ipairs(c.functions) do
        if i > 8 then break end
        table.insert(fn_names, f.name)
    end
    return string.format(
        "score=%d source=%s class=%s\n  full=%s\n  props=[%s]\n  funcs=[%s]\n",
        c.score, c.source, c.class_name, c.full_name,
        table.concat(prop_names, ", "), table.concat(fn_names, ", ")
    )
end

function Probe.run_dump()
    Util.log("%s", "=== FoW reflection dump start ===")
    local bucket = { _seen = {} }
    dump_priority_classes(bucket)
    dump_uobject_scan(bucket)
    bucket._seen = nil

    table.sort(bucket, function(a, b)
        if a.score == b.score then return a.full_name < b.full_name end
        return a.score > b.score
    end)

    local max_log = Config.MaxCandidatesLogged or 120
    local lines = {
        string.format("# MapSync FoW dump %s\n", os.date("!%Y-%m-%dT%H:%M:%SZ")),
        string.format("# candidates=%d\n\n", #bucket),
    }
    for i, c in ipairs(bucket) do
        if i > max_log then break end
        local block = format_candidate(c)
        table.insert(lines, block)
        Util.log("[%d] %s", i, (block:gsub("\n", " | ")))
    end

    local dir = Util.temp_queue_dir("MapSyncLogs")
    local path = string.format("%s\\fow_dump_%s.txt", dir, os.date("%Y%m%d_%H%M%S"))
    local ok, err = Util.write_text_file(path, table.concat(lines))
    if ok then
        Probe.LastDumpPath = path
        Util.log("dump written to %s", path)
    else
        Util.log("failed to write dump: %s", tostring(err))
    end

    Probe.LastCandidates = bucket
    Util.log("%s", "=== FoW reflection dump end ===")
    return bucket
end

return Probe
