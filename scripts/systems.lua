---@alias Button ecs.imgui.components.Button
---@alias GameActions ecs.game.GameActions
---@alias ButtonClose logic.ButtonClose

local system = require("scripts.lib.system")
local components = require("scripts.lib.components")
local Button = components.ecs.imgui.components.Button
local GameActions = components.ecs.game.GameActions
local ButtonClose = components.logic.ButtonClose
local ButtonOpen = components.logic.ButtonOpen

local query = require("scripts.lib.query")

---@param button Query<[Button, ButtonClose]>
---@param actions Query<[GameActions]>
local function close_run(button, actions)
	local _, close_button, _ = query.single(button)
	if close_button.clicked then
		local _, game_actions = query.single(actions)
		game_actions.should_close = true
	end
end

---@param buttons Query<[Button]>
---@param actions Query<[GameActions]>
local function click_run(buttons, actions)
	for button in query.iter(buttons) do
		---@cast button Button
		if button.clicked then
			print("Got button click of " .. button.title)
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

local called = 1
local function change_title(buttons)
	local _, button, _ = query.single(buttons)
	---@cast button Button
	if button.clicked then
		button.title = "Clicked " .. tostring(called) .. " times"
		called = called + 1
	end
end

return {
	system.new(click_run):query(Button):query(GameActions),
	system.new(close_run):query(Button, ButtonClose):query(GameActions),
	system.new(change_title):query(Button, ButtonOpen),
}
