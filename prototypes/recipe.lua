-- prototypes/recipe.lua

local C = require("prototypes.constants")

data:extend({
  {
    type = "recipe",
    name = C.RECIPE_NAME,
    enabled = false, -- unlocked by the circuit-network technology below
    energy_required = 0.5,
    ingredients = {
      -- Built on top of a real decider combinator: it is, conceptually, an
      -- enhanced one.
      { type = "item", name = "decider-combinator", amount = 1 },
      { type = "item", name = "electronic-circuit", amount = 5 },
      { type = "item", name = "copper-cable", amount = 5 },
    },
    results = {
      { type = "item", name = C.ITEM_NAME, amount = 1 },
    },
  },
})

-- Unlock alongside the vanilla combinators (circuit-network technology).
local tech = data.raw.technology["circuit-network"]
if tech then
  tech.effects = tech.effects or {}
  table.insert(tech.effects, { type = "unlock-recipe", recipe = C.RECIPE_NAME })
end
