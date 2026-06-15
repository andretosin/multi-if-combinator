-- settings.lua
-- Startup-only settings. Kept startup (not runtime) so the per-tick processing
-- interval is fixed for a save: the scheduler buckets combinators by
-- unit_number % interval, and a stable interval keeps those buckets valid.

data:extend({
  {
    type = "int-setting",
    name = "multi-if-combinator-update-interval",
    setting_type = "startup",
    -- Ticks between re-evaluations of each combinator. 20 = 3 updates/sec, plenty
    -- responsive for inventory balancing while spreading work across ticks.
    default_value = 20,
    minimum_value = 1,
    maximum_value = 600,
    order = "a",
  },
})
