-- prototypes/constants.lua
-- Shared values used across the data-stage prototype files.

return {
  -- Internal names.
  ENTITY_NAME = "multi-if-combinator",
  OUTPUT_NAME = "multi-if-combinator-output", -- hidden constant combinator that emits the result
  ITEM_NAME   = "multi-if-combinator",
  RECIPE_NAME = "multi-if-combinator",

  -- Orange tint applied to the reused decider-combinator sprites/icons so the
  -- entity reads as a distinct device at a glance.
  TINT = { r = 1.0, g = 0.62, b = 0.25, a = 1.0 },

  -- Base game decider combinator icon, reused (tinted) for our item/recipe/entity.
  DECIDER_ICON      = "__base__/graphics/icons/decider-combinator.png",
  DECIDER_ICON_SIZE = 64,

  -- A 1x1 fully transparent sprite for the invisible hidden output combinator.
  EMPTY_SPRITE = {
    filename = "__core__/graphics/empty.png",
    priority = "very-low",
    width = 1,
    height = 1,
  },
}
