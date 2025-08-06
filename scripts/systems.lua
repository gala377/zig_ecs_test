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
	local close_button, _ = query.single(button)
	---@cast close_button Button
	if close_button.clicked then
		local game_actions = query.single(actions)
		---@cast game_actions GameActions
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
			local ga = query.single(actions)
			---@cast ga GameActions
			ga.test_field = (ga.test_field or 0) + 1
			print("clicked " .. tostring(ga.test_field) .. " times")
			ga.log[#ga.log + 1] = button.title
			for i, log in ipairs(ga.log) do
				print("log " .. tostring(i) .. " " .. log)
			end
		end
	end
end

local called = 1
local function change_title(buttons)
	local button, _ = query.single(buttons)
	---@cast button Button
	if button.clicked then
		button.title = "Clicked " .. tostring(called) .. " times"
		called = called + 1
	end
end

return {
	system.new(click_run, "click logger"):query(Button):query(GameActions),
	system.new(close_run, "close on click"):query(Button, ButtonClose):query(GameActions),
	system.new(change_title, "change button title"):query(Button, ButtonOpen),
}
