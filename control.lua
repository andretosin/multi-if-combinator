-- control.lua
-- Multi-If Combinator runtime.
--
-- Each placed combinator pairs a player-facing decider-combinator (used only for
-- its input/output circuit poles + visuals) with an invisible constant
-- combinator wired to its OUTPUT poles. Every update we:
--   1. read the merged red/green signals on the INPUT poles,
--   2. evaluate each configured "IF <input> <op> <value/signal>" row,
--   3. for the rows that pass, write "<output signal> = <output value>" onto the
--      hidden constant combinator, which emits them on the OUTPUT network.
--
-- Input and output live on separate networks, so outputs never feed back into
-- the conditions (the whole point of the hidden-combinator technique).
--
-- UPS: combinators are bucketed by (unit_number % interval) and only the bucket
-- for the current tick is processed. Each combinator also caches the signature
-- of its last output and skips rewriting the constant combinator when nothing
-- changed (the common steady state).

-- =============================================================================
-- Constants
-- =============================================================================

local ENTITY_NAME = "multi-if-combinator"
local OUTPUT_NAME = "multi-if-combinator-output"

local UPDATE_INTERVAL =
  math.max(1, math.floor(settings.startup["multi-if-combinator-update-interval"].value))

-- How often open GUIs refresh their live input-count readouts (ticks).
local GUI_REFRESH_INTERVAL = 15

local IN_RED   = defines.wire_connector_id.combinator_input_red
local IN_GREEN = defines.wire_connector_id.combinator_input_green
local OUT_RED  = defines.wire_connector_id.combinator_output_red
local OUT_GREEN = defines.wire_connector_id.combinator_output_green
local CC_RED   = defines.wire_connector_id.circuit_red
local CC_GREEN = defines.wire_connector_id.circuit_green

-- Operators, in dropdown order. The symbols double as the stored operator value.
-- Literal UTF-8 characters (not \u escapes) so this parses under Factorio's Lua 5.2.
local OPERATORS = { "<", ">", "=", "≥", "≤", "≠" }
local OP_INDEX = {}
for i, op in ipairs(OPERATORS) do
  OP_INDEX[op] = i
end

-- Name filter shared by all build/remove event subscriptions.
local NAME_FILTER = { { filter = "name", name = ENTITY_NAME } }

-- =============================================================================
-- Small helpers
-- =============================================================================

-- Stable per-signal key (quality is intentionally ignored: "iron < 500" should
-- consider all qualities of iron together).
local function signal_key(sig)
  return (sig.type or "item") .. "/" .. sig.name
end

-- Deep-copy a conditions array (plain numbers/strings + flat SignalID tables),
-- dependency-free so we don't rely on util being loaded.
local function copy_conditions(conditions)
  local out = {}
  for i, cond in ipairs(conditions or {}) do
    local c = {
      operator = cond.operator,
      compare_value = cond.compare_value,
      output_value = cond.output_value,
    }
    if cond.input_signal then
      c.input_signal = { type = cond.input_signal.type, name = cond.input_signal.name }
    end
    if cond.compare_signal then
      c.compare_signal = { type = cond.compare_signal.type, name = cond.compare_signal.name }
    end
    if cond.output_signal then
      c.output_signal = { type = cond.output_signal.type, name = cond.output_signal.name }
    end
    out[i] = c
  end
  return out
end

local function default_condition()
  return { operator = "<", compare_value = 0, output_value = 0 }
end

-- Display form of a signal count shown under each input. Kept raw (no thousands
-- separator) to stay unambiguous across locales.
local function format_count(n)
  return tostring(n)
end

-- =============================================================================
-- Storage
-- =============================================================================
-- storage.combinators[unit_number] = {
--   entity     = LuaEntity,  -- player-facing combinator
--   output     = LuaEntity,  -- hidden constant combinator
--   conditions = { {input_signal, operator, compare_signal?, compare_value, output_signal, output_value}, ... },
--   last_sig   = string|false, -- signature of the last applied output
-- }
-- storage.schedule[phase][unit_number] = true   -- tick buckets
-- storage.guis[player_index] = { unit_number = N }

local function init_storage()
  storage.combinators = storage.combinators or {}
  storage.schedule = storage.schedule or {}
  storage.guis = storage.guis or {}
end

-- =============================================================================
-- Scheduler (UPS bucketing)
-- =============================================================================

local function schedule_add(unit_number)
  local phase = unit_number % UPDATE_INTERVAL
  local bucket = storage.schedule[phase]
  if not bucket then
    bucket = {}
    storage.schedule[phase] = bucket
  end
  bucket[unit_number] = true
end

local function schedule_remove(unit_number)
  local bucket = storage.schedule[unit_number % UPDATE_INTERVAL]
  if bucket then
    bucket[unit_number] = nil
  end
end

local function rebuild_schedule()
  storage.schedule = {}
  for unit_number in pairs(storage.combinators) do
    schedule_add(unit_number)
  end
end

-- =============================================================================
-- Hidden output combinator wiring
-- =============================================================================

-- Connects the hidden constant combinator's output to the main entity's OUTPUT
-- poles using invisible script wires (not player-editable, not drawn).
local function wire_output(entity, output)
  local cc_red = output.get_wire_connector(CC_RED, true)
  local cc_green = output.get_wire_connector(CC_GREEN, true)
  local main_red = entity.get_wire_connector(OUT_RED, true)
  local main_green = entity.get_wire_connector(OUT_GREEN, true)
  cc_red.connect_to(main_red, false, defines.wire_origin.script)
  cc_green.connect_to(main_green, false, defines.wire_origin.script)
end

local function create_output(entity)
  local output = entity.surface.create_entity({
    name = OUTPUT_NAME,
    position = entity.position,
    force = entity.force,
    create_build_effect_smoke = false,
  })
  if not output then
    return nil
  end
  output.destructible = false
  wire_output(entity, output)
  return output
end

-- =============================================================================
-- Registration / cleanup
-- =============================================================================

local function register_combinator(entity, conditions)
  local output = create_output(entity)
  if not output then
    return nil
  end
  local data = {
    entity = entity,
    output = output,
    conditions = conditions or {},
    last_sig = false,
  }
  storage.combinators[entity.unit_number] = data
  schedule_add(entity.unit_number)
  return data
end

-- Close any open GUI that points at a now-gone combinator.
local function close_guis_for(unit_number)
  for player_index, g in pairs(storage.guis) do
    if g.unit_number == unit_number then
      local player = game.get_player(player_index)
      if player then
        local frame = player.gui.screen.multi_if_main_frame
        if frame then
          frame.destroy()
        end
      end
      storage.guis[player_index] = nil
    end
  end
end

local function unregister_combinator(unit_number)
  local data = storage.combinators[unit_number]
  if not data then
    return
  end
  if data.output and data.output.valid then
    data.output.destroy()
  end
  storage.combinators[unit_number] = nil
  schedule_remove(unit_number)
  close_guis_for(unit_number)
end

-- =============================================================================
-- Signal evaluation
-- =============================================================================

-- Merge the red + green input networks into a { key -> count } table.
local function read_inputs(entity)
  local inputs = {}
  local nets = { entity.get_circuit_network(IN_RED), entity.get_circuit_network(IN_GREEN) }
  for _, net in pairs(nets) do
    if net then
      local signals = net.signals
      if signals then
        for _, s in pairs(signals) do
          local key = signal_key(s.signal)
          inputs[key] = (inputs[key] or 0) + s.count
        end
      end
    end
  end
  return inputs
end

local function signal_value(inputs, sig)
  if not sig then
    return 0
  end
  return inputs[signal_key(sig)] or 0
end

local function evaluate(cond, inputs)
  local lhs = signal_value(inputs, cond.input_signal)
  local rhs
  if cond.compare_signal then
    rhs = signal_value(inputs, cond.compare_signal)
  else
    rhs = cond.compare_value or 0
  end

  local op = cond.operator
  if op == "<" then
    return lhs < rhs
  elseif op == ">" then
    return lhs > rhs
  elseif op == "=" then
    return lhs == rhs
  elseif op == "≥" then
    return lhs >= rhs
  elseif op == "≤" then
    return lhs <= rhs
  elseif op == "≠" then
    return lhs ~= rhs
  end
  return false
end

-- Write the computed outputs onto the hidden constant combinator, skipping the
-- write entirely when the result is identical to last time.
local function apply_output(data, outputs)
  -- Deterministic signature so unchanged results can be cheaply detected.
  local keys = {}
  if outputs then
    for key in pairs(outputs) do
      keys[#keys + 1] = key
    end
    table.sort(keys)
  end

  local filters = {}
  local parts = {}
  for _, key in ipairs(keys) do
    local o = outputs[key]
    filters[#filters + 1] = {
      value = {
        type = o.sig.type or "item",
        name = o.sig.name,
        quality = "normal",
        comparator = "=",
      },
      min = o.count,
    }
    parts[#parts + 1] = key .. "=" .. o.count
  end

  local sig = table.concat(parts, ";")
  if data.last_sig == sig then
    return
  end
  data.last_sig = sig

  local output = data.output
  if not (output and output.valid) then
    return
  end

  local cb = output.get_or_create_control_behavior()
  -- Keep exactly one section and overwrite its filters.
  local section = cb.get_section(1) or cb.add_section()
  if not section then
    return
  end
  while cb.sections_count > 1 do
    cb.remove_section(cb.sections_count)
  end
  section.filters = filters
  cb.enabled = true
end

local function process(unit_number)
  local data = storage.combinators[unit_number]
  if not data then
    schedule_remove(unit_number)
    return
  end

  local entity = data.entity
  if not (entity and entity.valid) then
    unregister_combinator(unit_number)
    return
  end

  local conditions = data.conditions
  local outputs
  if conditions and #conditions > 0 then
    local inputs = read_inputs(entity)
    for _, cond in pairs(conditions) do
      -- A row only contributes once it has both an input and an output signal.
      if cond.input_signal and cond.output_signal and evaluate(cond, inputs) then
        local osig = cond.output_signal
        local key = signal_key(osig)
        outputs = outputs or {}
        local existing = outputs[key]
        if existing then
          existing.count = existing.count + (cond.output_value or 0)
        else
          outputs[key] = { sig = osig, count = cond.output_value or 0 }
        end
      end
    end
  end

  apply_output(data, outputs)
end

-- =============================================================================
-- GUI
-- =============================================================================

local function get_gui_data(player)
  local g = storage.guis[player.index]
  if not g then
    return nil
  end
  local data = storage.combinators[g.unit_number]
  if not data or not (data.entity and data.entity.valid) then
    return nil
  end
  return data
end

local function find_table(player)
  local frame = player.gui.screen.multi_if_main_frame
  if not frame then
    return nil
  end
  return frame.content.rows_scroll.rows_table
end

-- (Re)builds the rows table from storage. Called on open and after structural
-- changes (add/remove/paste). Value edits update storage in place without a
-- rebuild so text fields keep focus.
local function refresh_rows(player, data)
  local tbl = find_table(player)
  if not tbl then
    return
  end
  tbl.clear()

  -- Snapshot of the input network so each row can show its current amount.
  local inputs = (data.entity and data.entity.valid) and read_inputs(data.entity) or {}

  -- Header row.
  tbl.add({ type = "label", style = "caption_label", caption = { "multi-if-combinator.col-input" } })
  tbl.add({ type = "label", style = "caption_label", caption = { "multi-if-combinator.col-operator" } })
  tbl.add({ type = "label", style = "caption_label", caption = { "multi-if-combinator.col-compare" } })
  tbl.add({ type = "empty-widget" })
  tbl.add({ type = "label", style = "caption_label", caption = { "multi-if-combinator.col-output" } })
  tbl.add({ type = "label", style = "caption_label", caption = { "multi-if-combinator.col-output-value" } })
  tbl.add({ type = "empty-widget" })

  for index, cond in ipairs(data.conditions) do
    -- Input signal + a live readout of how much of it is on the input network,
    -- so the player can see at a glance what is currently lacking.
    local input_wrap = tbl.add({ type = "flow", name = "inwrap_" .. index, direction = "vertical" })
    input_wrap.style.horizontal_align = "center"
    local input_btn = input_wrap.add({
      type = "choose-elem-button",
      elem_type = "signal",
      tags = { multi_if = true, action = "input_signal", index = index },
    })
    input_btn.elem_value = cond.input_signal
    local count_label = input_wrap.add({
      type = "label",
      name = "count_" .. index,
      caption = cond.input_signal and format_count(signal_value(inputs, cond.input_signal)) or "",
      tooltip = { "multi-if-combinator.input-count-tooltip" },
    })
    count_label.style.font_color = { 0.85, 0.85, 0.85 }

    -- Operator.
    tbl.add({
      type = "drop-down",
      items = OPERATORS,
      selected_index = OP_INDEX[cond.operator] or 1,
      tags = { multi_if = true, action = "operator", index = index },
    })

    -- Comparison: a signal (takes precedence) OR a constant value.
    local compare_flow = tbl.add({ type = "flow", direction = "horizontal" })
    compare_flow.style.vertical_align = "center"
    local compare_btn = compare_flow.add({
      type = "choose-elem-button",
      elem_type = "signal",
      tooltip = { "multi-if-combinator.compare-signal-tooltip" },
      tags = { multi_if = true, action = "compare_signal", index = index },
    })
    compare_btn.elem_value = cond.compare_signal
    local compare_value = compare_flow.add({
      type = "textfield",
      text = tostring(cond.compare_value or 0),
      numeric = true,
      allow_negative = true,
      allow_decimal = false,
      tooltip = { "multi-if-combinator.compare-value-tooltip" },
      tags = { multi_if = true, action = "compare_value", index = index },
    })
    compare_value.style.width = 70
    -- When a comparison signal is chosen, the constant value is ignored.
    compare_value.enabled = (cond.compare_signal == nil)

    -- Arrow.
    tbl.add({ type = "label", caption = "→" })

    -- Output signal.
    local output_btn = tbl.add({
      type = "choose-elem-button",
      elem_type = "signal",
      tags = { multi_if = true, action = "output_signal", index = index },
    })
    output_btn.elem_value = cond.output_signal

    -- Output value.
    local output_value = tbl.add({
      type = "textfield",
      text = tostring(cond.output_value or 0),
      numeric = true,
      allow_negative = true,
      allow_decimal = false,
      tags = { multi_if = true, action = "output_value", index = index },
    })
    output_value.style.width = 70

    -- Remove row.
    tbl.add({
      type = "sprite-button",
      style = "tool_button_red",
      sprite = "utility/trash",
      tooltip = { "multi-if-combinator.remove-row-tooltip" },
      tags = { multi_if = true, action = "remove_row", index = index },
    })
  end
end

-- Refresh just the per-row input-count labels of one open GUI (cheap; no rebuild).
local function update_gui_inputs(player, data)
  if not (data.entity and data.entity.valid) then
    return
  end
  local tbl = find_table(player)
  if not tbl then
    return
  end
  local inputs = read_inputs(data.entity)
  for index, cond in ipairs(data.conditions) do
    local wrap = tbl["inwrap_" .. index]
    if wrap and wrap.valid then
      local label = wrap["count_" .. index]
      if label and label.valid then
        label.caption = cond.input_signal and format_count(signal_value(inputs, cond.input_signal)) or ""
      end
    end
  end
end

-- Update every open GUI's live input counts.
local function update_open_guis()
  for player_index, g in pairs(storage.guis) do
    local data = storage.combinators[g.unit_number]
    local player = game.get_player(player_index)
    if player and data then
      update_gui_inputs(player, data)
    end
  end
end

local function build_gui(player, unit_number)
  -- Close any previous instance first.
  local existing = player.gui.screen.multi_if_main_frame
  if existing then
    existing.destroy()
  end

  local data = storage.combinators[unit_number]
  if not data then
    return
  end

  local frame = player.gui.screen.add({
    type = "frame",
    name = "multi_if_main_frame",
    direction = "vertical",
  })
  frame.auto_center = true

  -- Title bar (draggable).
  local titlebar = frame.add({ type = "flow", direction = "horizontal" })
  titlebar.drag_target = frame
  titlebar.add({
    type = "label",
    style = "frame_title",
    caption = { "multi-if-combinator.gui-title" },
    ignored_by_interaction = true,
  })
  local filler = titlebar.add({ type = "empty-widget", style = "draggable_space_header" })
  filler.style.height = 24
  filler.style.horizontally_stretchable = true
  filler.ignored_by_interaction = true
  titlebar.add({
    type = "sprite-button",
    style = "frame_action_button",
    sprite = "utility/close",
    tooltip = { "multi-if-combinator.close-tooltip" },
    tags = { multi_if = true, action = "close" },
  })

  -- Body.
  local content = frame.add({
    type = "frame",
    name = "content",
    style = "inside_shallow_frame_with_padding",
    direction = "vertical",
  })

  content.add({
    type = "label",
    caption = { "multi-if-combinator.gui-help" },
    single_line = false,
  }).style.bottom_margin = 8

  local scroll = content.add({
    type = "scroll-pane",
    name = "rows_scroll",
    direction = "vertical",
  })
  scroll.style.maximal_height = 420
  scroll.style.minimal_width = 640

  scroll.add({
    type = "table",
    name = "rows_table",
    column_count = 7,
  })
  scroll.rows_table.style.horizontal_spacing = 8
  scroll.rows_table.style.vertical_spacing = 6

  local footer = content.add({ type = "flow", direction = "horizontal" })
  footer.style.top_margin = 8
  footer.add({
    type = "button",
    caption = { "multi-if-combinator.add-condition" },
    tags = { multi_if = true, action = "add_row" },
  })

  storage.guis[player.index] = { unit_number = unit_number }
  refresh_rows(player, data)

  player.opened = frame
end

-- =============================================================================
-- GUI events
-- =============================================================================

script.on_event(defines.events.on_gui_opened, function(event)
  if event.gui_type ~= defines.gui_type.entity then
    return
  end
  local entity = event.entity
  if not (entity and entity.valid and entity.name == ENTITY_NAME) then
    return
  end
  local player = game.get_player(event.player_index)
  if player then
    build_gui(player, entity.unit_number)
  end
end)

script.on_event(defines.events.on_gui_closed, function(event)
  local element = event.element
  if element and element.valid and element.name == "multi_if_main_frame" then
    element.destroy()
    storage.guis[event.player_index] = nil
  end
end)

script.on_event(defines.events.on_gui_click, function(event)
  local element = event.element
  if not (element and element.valid and element.tags and element.tags.multi_if) then
    return
  end
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  local action = element.tags.action

  if action == "close" then
    local frame = player.gui.screen.multi_if_main_frame
    if frame then
      frame.destroy()
    end
    storage.guis[player.index] = nil
    return
  end

  local data = get_gui_data(player)
  if not data then
    local frame = player.gui.screen.multi_if_main_frame
    if frame then
      frame.destroy()
    end
    storage.guis[player.index] = nil
    return
  end

  if action == "add_row" then
    table.insert(data.conditions, default_condition())
    data.last_sig = false
    refresh_rows(player, data)
  elseif action == "remove_row" then
    table.remove(data.conditions, element.tags.index)
    data.last_sig = false
    refresh_rows(player, data)
  end
end)

script.on_event(defines.events.on_gui_elem_changed, function(event)
  local element = event.element
  if not (element and element.valid and element.tags and element.tags.multi_if) then
    return
  end
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  local data = get_gui_data(player)
  if not data then
    return
  end
  local cond = data.conditions[element.tags.index]
  if not cond then
    return
  end

  local action = element.tags.action
  if action == "input_signal" then
    cond.input_signal = element.elem_value
  elseif action == "output_signal" then
    cond.output_signal = element.elem_value
  elseif action == "compare_signal" then
    cond.compare_signal = element.elem_value
    -- Re-render so the constant-value field enables/disables accordingly.
    refresh_rows(player, data)
  end
  data.last_sig = false
end)

script.on_event(defines.events.on_gui_text_changed, function(event)
  local element = event.element
  if not (element and element.valid and element.tags and element.tags.multi_if) then
    return
  end
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  local data = get_gui_data(player)
  if not data then
    return
  end
  local cond = data.conditions[element.tags.index]
  if not cond then
    return
  end

  local n = math.floor(tonumber(element.text) or 0)
  local action = element.tags.action
  if action == "compare_value" then
    cond.compare_value = n
  elseif action == "output_value" then
    cond.output_value = n
  end
  data.last_sig = false
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
  local element = event.element
  if not (element and element.valid and element.tags and element.tags.multi_if) then
    return
  end
  if element.tags.action ~= "operator" then
    return
  end
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  local data = get_gui_data(player)
  if not data then
    return
  end
  local cond = data.conditions[element.tags.index]
  if not cond then
    return
  end
  cond.operator = OPERATORS[element.selected_index] or "<"
  data.last_sig = false
end)

-- =============================================================================
-- Build / remove events
-- =============================================================================

local function on_built(event)
  local entity = event.entity or event.created_entity
  if not (entity and entity.valid and entity.name == ENTITY_NAME) then
    return
  end
  local conditions
  if event.tags and event.tags.multi_if_conditions then
    conditions = copy_conditions(event.tags.multi_if_conditions)
  end
  register_combinator(entity, conditions)
end

local function on_removed(event)
  local entity = event.entity
  if not (entity and entity.valid and entity.name == ENTITY_NAME) then
    return
  end
  unregister_combinator(entity.unit_number)
end

for _, ev in ipairs({
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.on_space_platform_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive,
}) do
  script.on_event(ev, on_built, NAME_FILTER)
end

for _, ev in ipairs({
  defines.events.on_player_mined_entity,
  defines.events.on_robot_mined_entity,
  defines.events.on_space_platform_mined_entity,
  defines.events.on_entity_died,
  defines.events.script_raised_destroy,
}) do
  script.on_event(ev, on_removed, NAME_FILTER)
end

-- =============================================================================
-- Copy/paste, blueprint, clone
-- =============================================================================

script.on_event(defines.events.on_entity_settings_pasted, function(event)
  local src, dst = event.source, event.destination
  if not (src and dst and src.valid and dst.valid) then
    return
  end
  if src.name ~= ENTITY_NAME or dst.name ~= ENTITY_NAME then
    return
  end
  local sdata = storage.combinators[src.unit_number]
  local ddata = storage.combinators[dst.unit_number]
  if not (sdata and ddata) then
    return
  end
  ddata.conditions = copy_conditions(sdata.conditions)
  ddata.last_sig = false
  -- Refresh any GUI currently showing the destination.
  for player_index, g in pairs(storage.guis) do
    if g.unit_number == dst.unit_number then
      local player = game.get_player(player_index)
      if player then
        refresh_rows(player, ddata)
      end
    end
  end
end)

script.on_event(defines.events.on_player_setup_blueprint, function(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end

  -- 2.0 provides the blueprint directly via event.stack; fall back to the older
  -- accessors for robustness across edit/library/cursor cases.
  local bp = event.stack
  if not (bp and bp.valid_for_read) then
    bp = player.blueprint_to_setup
  end
  if not (bp and bp.valid_for_read) then
    bp = player.cursor_stack
  end
  if not (bp and bp.valid_for_read and bp.is_blueprint) then
    return
  end

  local entities = bp.get_blueprint_entities()
  if not entities then
    return
  end

  if not event.mapping then
    return
  end
  -- mapping is keyed by each blueprint entity's entity_number (not array index),
  -- and set_blueprint_entity_tag expects that same number.
  local mapping = event.mapping.get()
  for _, bpe in ipairs(entities) do
    if bpe.name == ENTITY_NAME then
      local number = bpe.entity_number
      local src = mapping[number]
      if src and src.valid then
        local data = storage.combinators[src.unit_number]
        if data and data.conditions and #data.conditions > 0 then
          bp.set_blueprint_entity_tag(number, "multi_if_conditions", copy_conditions(data.conditions))
        end
      end
    end
  end
end)

script.on_event(defines.events.on_entity_cloned, function(event)
  local dst = event.destination
  if not (dst and dst.valid) then
    return
  end

  -- A cloned hidden combinator is an orphan: the cloned main entity will create
  -- its own. Destroy it.
  if dst.name == OUTPUT_NAME then
    dst.destroy()
    return
  end

  if dst.name ~= ENTITY_NAME then
    return
  end

  local conditions
  local src = event.source
  if src and src.valid and src.name == ENTITY_NAME then
    local sdata = storage.combinators[src.unit_number]
    if sdata then
      conditions = copy_conditions(sdata.conditions)
    end
  end

  if not storage.combinators[dst.unit_number] then
    register_combinator(dst, conditions)
  end
end)

-- =============================================================================
-- Tick processing
-- =============================================================================

script.on_event(defines.events.on_tick, function(event)
  local tick = event.tick
  local bucket = storage.schedule[tick % UPDATE_INTERVAL]
  if bucket then
    for unit_number in pairs(bucket) do
      process(unit_number)
    end
  end
  -- Keep the live input-count readouts in any open GUI fresh.
  if tick % GUI_REFRESH_INTERVAL == 0 then
    update_open_guis()
  end
end)

-- =============================================================================
-- Lifecycle
-- =============================================================================

script.on_init(function()
  init_storage()
  rebuild_schedule()
end)

script.on_configuration_changed(function()
  init_storage()
  -- Revalidate every combinator: drop dead ones, recreate missing hidden
  -- outputs, and force a rewrite on the next tick.
  for unit_number, data in pairs(storage.combinators) do
    if not (data.entity and data.entity.valid) then
      if data.output and data.output.valid then
        data.output.destroy()
      end
      storage.combinators[unit_number] = nil
    else
      if not (data.output and data.output.valid) then
        data.output = create_output(data.entity)
      end
      data.last_sig = false
    end
  end
  rebuild_schedule()
end)
