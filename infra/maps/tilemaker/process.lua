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

local function add_class(value)
  if value ~= "" then
    Attribute("class", value)
  end
end

function node_function()
  -- Style v1 has no point layers. Keeping this function explicit prevents
  -- accidental inclusion of POI names or other unnecessary personal context.
end

function way_function()
  local natural = Find("natural")
  local water = Find("water")
  local waterway = Find("waterway")
  if natural == "water" or water_values[water] or waterway == "riverbank" then
    Layer("water", true)
    add_class(water ~= "" and water or natural)
    return
  end

  local leisure = Find("leisure")
  local landuse = Find("landuse")
  if leisure == "park" or landuse_values[landuse] then
    Layer("landuse", true)
    add_class(leisure ~= "" and leisure or landuse)
    return
  end

  local highway = Find("highway")
  if highway ~= "" then
    Layer("transportation", false)
    add_class(highway)
  end
end
