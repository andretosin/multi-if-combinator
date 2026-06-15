-- prototypes/item.lua

local C = require("prototypes.constants")

data:extend({
  {
    type = "item",
    name = C.ITEM_NAME,
    icons = {
      { icon = C.DECIDER_ICON, icon_size = C.DECIDER_ICON_SIZE, tint = C.TINT },
    },
    subgroup = "circuit-network",
    -- Order it right after the vanilla decider combinator in the build menu.
    order = "c[combinators]-cc[multi-if-combinator]",
    place_result = C.ENTITY_NAME,
    stack_size = 50,
  },
})
