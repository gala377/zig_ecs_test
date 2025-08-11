---@alias Button ecs.imgui.components.Button
---@alias GameActions ecs.game.GameActions
---@alias ButtonClose logic.ButtonClose

local query = require("scripts.lib.query")
local system = require("scripts.lib.system")

local Button = ecs.imgui.components.Button
local GameActions = ecs.game.GameActions
local ButtonClose = logic.ButtonClose
local ButtonOpen = logic.ButtonOpen

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
			local ga = query.single(actions)
			---@cast ga GameActions
			ga.test_field = (ga.test_field or 0) + 1
		end
	end
end

local called = 1
---@param buttons Query<[Button, logic.ButtonOpen]>
local function change_title(buttons)
	local button, _ = query.single(buttons)
	---@cast button Button
	if button.clicked then
		called = called + 1
	end
end

return {
	system.new(click_run, "click logger"):query(Button):query(GameActions),
	system.new(close_run, "close on click"):query(Button, ButtonClose):query(GameActions),
	system.new(change_title, "change button title"):query(Button, ButtonOpen),
}
