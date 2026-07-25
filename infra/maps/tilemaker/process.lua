-- Minimal deterministic Tilemaker profile for the Monaco staging extract.
-- It intentionally emits only layers consumed by style v1.

local water_values = {
  bay = true,
  reservoir = true,
  water = true,
}

local landuse_values = {
  cemetery = true,
  commercial = true,
  forest = true,
  grass = true,
  industrial = true,
  meadow = true,
  military = true,
  park = true,
  residential = true,
  retail = true,
}

local function add_class(object, value)
  if value ~= "" then
    object:Attribute("class", value)
  end
end

function node_function(_node)
  -- Style v1 has no point layers. Keeping this function explicit prevents
  -- accidental inclusion of POI names or other unnecessary personal context.
end

function way_function(way)
  local natural = way:Find("natural")
  local water = way:Find("water")
  local waterway = way:Find("waterway")
  if natural == "water" or water_values[water] or waterway == "riverbank" then
    way:Layer("water", true)
    add_class(way, water ~= "" and water or natural)
    return
  end

  local leisure = way:Find("leisure")
  local landuse = way:Find("landuse")
  if leisure == "park" or landuse_values[landuse] then
    way:Layer("landuse", true)
    add_class(way, leisure ~= "" and leisure or landuse)
    return
  end

  local highway = way:Find("highway")
  if highway ~= "" then
    way:Layer("transportation", false)
    add_class(way, highway)
  end
end
