---@alias Button ecs.imgui.components.Button
---@alias GameActions ecs.game.GameActions

local system = require("scripts.lib.system")
local components = require("scripts.lib.components")
local Button = components.ecs.imgui.components.Button
local GameActions = components.ecs.game.GameActions

local query = require("scripts.lib.query")

---@alias SystemParams [Button]
---@param buttons Query<SystemParams>
---@param actions Query<GameActions>
local function run(buttons, actions)
	for button in query.iter(buttons) do
		---@cast button Button
		if button.clicked then
			print("Got button click!")
			---@type boolean, GameActions
			local _, ga = query.single(actions)
			if ga.test_field == nil then
				ga.test_field = 1
			else
				ga.test_field = ga.test_field + 1
			end
			print("clicked " .. tostring(ga.test_field) .. " times")
		end
	end
end

return system.new(run):query(Button):query(GameActions)
