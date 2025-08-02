local system = require("scripts.lib.system")
local components = require("scripts.lib.components")
local Button = components.ecs.imgui.components.Button
local ButtonClose = components.logic.ButtonClose
local GameActions = components.ecs.game.GameActions

local query = require("scripts.lib.query").query

---@param buttons Query<[Button, logic.ButtonClose]>
---@param game_actions Query<[GameActions]>
local function run(buttons, game_actions)
	for button, _ in query(buttons) do
		if button.clicked then
			print("Closing game!")
			for actions in query(game_actions) do
				actions.should_close = true
			end
		end
	end
end

return system.new(run):query(Button, ButtonClose):query(GameActions)
