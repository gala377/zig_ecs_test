---@alias Button ecs.imgui.components.Button
---@alias GameActions ecs.runtime.components.GameActions
---@alias ButtonClose logic.ButtonClose

local query = require("scripts.lib.query")
local system = require("scripts.lib.system")

local Button = ecs.imgui.components.Button
local GameActions = ecs.runtime.components.GameActions
local ButtonClose = logic.ButtonClose
local ButtonOpen = logic.ButtonOpen

---@param button Query<[Button, ButtonClose]>
---@param actions GameActions
local function close_run(button, actions)
	local close_button, _ = query.single(button)
	---@cast close_button Button
	if close_button.clicked then
		actions.should_close = true
	end
end

---@param buttons Query<[Button]>
---@param actions GameActions
local function click_run(buttons, actions)
	for button in query.iter(buttons) do
		if button.clicked then
			print("Button clicked from lua")
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
	system.new(click_run, "click logger"):arguments({ Button }, GameActions),
	system.new(close_run, "close on click"):arguments({ Button, ButtonClose }, GameActions),
	system.new(change_title, "change button title"):arguments { Button, ButtonOpen },
}
