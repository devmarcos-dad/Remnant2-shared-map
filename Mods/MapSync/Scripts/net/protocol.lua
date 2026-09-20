local Config = require("config")

local Protocol = {}

function Protocol.magic()
    return (Config.Lan and Config.Lan.Magic) or "MS01"
end

function Protocol.encode_hello(role, seq)
    return string.format("%s|HELLO|%s|%d|%d", Protocol.magic(), tostring(role or "?"), seq or 0, os.time())
end

function Protocol.encode_bye(role, seq)
    return string.format("%s|BYE|%s|%d", Protocol.magic(), tostring(role or "?"), seq or 0)
end

function Protocol.encode_fog(fog_enabled, seq)
    local bit = (fog_enabled and 1) or 0
    return string.format("%s|FOG|%d|%d", Protocol.magic(), bit, seq or 0)
end

function Protocol.encode_tile(zone_id, x, y, seq)
    return string.format(
        "%s|TILE|%d|%d|%d|%d",
        Protocol.magic(),
        tonumber(zone_id) or 0,
        tonumber(x) or 0,
        tonumber(y) or 0,
        seq or 0
    )
end

function Protocol.encode_tiles(tiles, seq)
    local parts = {}
    for _, t in ipairs(tiles or {}) do
        table.insert(parts, string.format("%d:%d:%d", t.zone or 0, t.x or 0, t.y or 0))
    end
    return string.format("%s|TILES|%s|%d", Protocol.magic(), table.concat(parts, ","), seq or 0)
end

function Protocol.encode_pos(x, y, z, seq)
    return string.format(
        "%s|POS|%.3f|%.3f|%.3f|%d",
        Protocol.magic(),
        tonumber(x) or 0,
        tonumber(y) or 0,
        tonumber(z) or 0,
        seq or 0
    )
end

function Protocol.decode(line)
    if line == nil or line == "" then return nil end
    line = tostring(line):gsub("\r", ""):gsub("\n", "")
    local parts = {}
    for piece in string.gmatch(line, "[^|]+") do
        table.insert(parts, piece)
    end
    if #parts < 2 or parts[1] ~= Protocol.magic() then return nil end
    local kind = parts[2]
    if kind == "HELLO" then
        return { kind = "HELLO", role = parts[3], seq = tonumber(parts[4]) or 0, unix = tonumber(parts[5]) or 0 }
    end
    if kind == "BYE" then
        return { kind = "BYE", role = parts[3], seq = tonumber(parts[4]) or 0 }
    end
    if kind == "FOG" then
        return { kind = "FOG", enabled = (tonumber(parts[3]) or 0) == 1, seq = tonumber(parts[4]) or 0 }
    end
    if kind == "TILE" then
        return {
            kind = "TILE",
            zone = tonumber(parts[3]) or 0,
            x = tonumber(parts[4]) or 0,
            y = tonumber(parts[5]) or 0,
            seq = tonumber(parts[6]) or 0,
        }
    end
    if kind == "TILES" then
        local tiles = {}
        for triple in string.gmatch(parts[3] or "", "[^,]+") do
            local z, x, y = string.match(triple, "^(%-?%d+):(%-?%d+):(%-?%d+)$")
            if z then
                table.insert(tiles, { zone = tonumber(z), x = tonumber(x), y = tonumber(y) })
            end
        end
        return { kind = "TILES", tiles = tiles, seq = tonumber(parts[4]) or 0 }
    end
    if kind == "POS" then
        return {
            kind = "POS",
            x = tonumber(parts[3]) or 0,
            y = tonumber(parts[4]) or 0,
            z = tonumber(parts[5]) or 0,
            seq = tonumber(parts[6]) or 0,
        }
    end
    return { kind = "UNKNOWN", raw = line }
end

return Protocol
