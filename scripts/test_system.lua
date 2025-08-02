---@alias Button ecs.imgui.components.Button
---@alias GameActions ecs.game.GameActions

local system = require("scripts.lib.system")
local components = require("scripts.lib.components")
local Button = components.ecs.imgui.components.Button

local query = require("scripts.lib.query").query

---@alias SystemParams [Button]
---@param buttons Query<SystemParams>
local function run(buttons)
	for comps in query(buttons) do
		local button = comps[1]
		if button.clicked then
			print("Got button click!")
		end
	end
end

return system.new(run):query(Button)
