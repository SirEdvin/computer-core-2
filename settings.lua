-- Bounded feasibility geometry. Final client-supported bounds are a section-4 gate.
data:extend({
  {type = "int-setting", name = "computer-core-terminal-columns", setting_type = "startup",
    default_value = 51, minimum_value = 1, maximum_value = 160, order = "terminal-a"},
  {type = "int-setting", name = "computer-core-terminal-rows", setting_type = "startup",
    default_value = 19, minimum_value = 1, maximum_value = 60, order = "terminal-b"}
})
