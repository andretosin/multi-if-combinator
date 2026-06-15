-- prototypes/entity.lua
-- Two entities:
--   1. multi-if-combinator         -> the player-facing combinator (cloned from
--      the vanilla decider combinator, so it has separate input/output circuit
--      poles and ready-made sprites). Tinted to look distinct.
--   2. multi-if-combinator-output  -> an invisible constant combinator created by
--      control.lua and wired to the main entity's OUTPUT poles. It is what
--      actually emits the computed signals, keeping input and output on separate
--      networks (no feedback loop).

local C = require("prototypes.constants")

-- =============================================================================
-- 1. Player-facing combinator (reskinned decider combinator)
-- =============================================================================

local combinator = table.deepcopy(data.raw["decider-combinator"]["decider-combinator"])

combinator.name = C.ENTITY_NAME
combinator.minable = { mining_time = 0.1, result = C.ITEM_NAME }
-- Don't let it fast-replace with / from a real decider combinator: the behaviour
-- and configuration are not interchangeable.
combinator.fast_replaceable_group = nil
combinator.next_upgrade = nil

-- Replace the inherited single icon with a tinted icons table.
combinator.icon = nil
combinator.icon_size = nil
combinator.icons = {
  { icon = C.DECIDER_ICON, icon_size = C.DECIDER_ICON_SIZE, tint = C.TINT },
}

-- Tint every non-shadow sprite layer of a Sprite4Way in place so the placed
-- entity is visibly different from a vanilla decider combinator. Shadows are
-- skipped so they stay black. Unknown shapes are left untouched.
local function tint_sprite4way(s4, tint)
  if type(s4) ~= "table" then return end
  for _, dir in pairs(s4) do
    if type(dir) == "table" then
      if dir.layers then
        for _, layer in pairs(dir.layers) do
          if type(layer) == "table" and not layer.draw_as_shadow then
            layer.tint = tint
          end
        end
      else
        dir.tint = tint
      end
    end
  end
end

tint_sprite4way(combinator.sprites, C.TINT)

-- =============================================================================
-- 2. Hidden output combinator (invisible constant combinator)
-- =============================================================================

-- Four identical connection points (one per direction); all wires are managed by
-- script at (0,0) relative to the entity.
local zero_connection_point = {
  wire   = { red = { 0, 0 }, green = { 0, 0 } },
  shadow = { red = { 0, 0 }, green = { 0, 0 } },
}

local hidden_output = {
  type = "constant-combinator",
  name = C.OUTPUT_NAME,

  -- Never shown anywhere, but provided so every code path that expects an entity
  -- icon is satisfied.
  icons = {
    { icon = C.DECIDER_ICON, icon_size = C.DECIDER_ICON_SIZE, tint = C.TINT },
  },

  -- Make it inert and invisible in every way.
  hidden = true,
  selectable_in_game = false,
  flags = {
    "placeable-off-grid",
    "not-on-map",
    "not-blueprintable",
    "not-deconstructable",
    "not-upgradable",
    "not-flammable",
    "hide-alt-info",
    "not-in-kill-statistics",
    "not-selectable-in-game",
    "no-automated-item-removal",
    "no-automated-item-insertion",
  },

  -- Collide with nothing so it can share the exact tile of the main combinator.
  collision_mask = { layers = {} },
  collision_box = { { 0, 0 }, { 0, 0 } },
  selection_box = nil,

  -- No item_slot_count in 2.0: output capacity comes from logistic sections,
  -- which we populate at runtime in control.lua.
  circuit_wire_max_distance = 3,
  draw_circuit_wires = false,

  sprites = C.EMPTY_SPRITE,
  activity_led_sprites = C.EMPTY_SPRITE,
  activity_led_light_offsets = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } },
  circuit_wire_connection_points = {
    zero_connection_point,
    zero_connection_point,
    zero_connection_point,
    zero_connection_point,
  },
}

data:extend({ combinator, hidden_output })
