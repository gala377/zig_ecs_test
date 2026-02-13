local query = require("scripts.lib.query")
local system = require("scripts.lib.system")

local Button = ecs.imgui.components.Button
local GameActions = ecs.runtime.game_actions
local ButtonClose = logic.ButtonClose
local ButtonOpen = logic.ButtonOpen
local Foo = logic.Foo

local function close_run(button, actions)
	local close_button, _ = query.single(button)
	if close_button ~= nil and close_button.clicked then
		actions.should_close = true
	end
end

local function click_run(buttons, foos, _)
	for button in query.iter(buttons) do
		if button.clicked then
			local foo = query.assertSingle(foos)
			if foo ~= nil then
				local bar = foo.bar
				bar.x = bar.x + 1
				foo:setBar { x = bar.x + 1, y = bar.y }
			end
		end
	end
end

local called = 1
local function change_title(buttons)
	local button, _ = query.assertSingle(buttons)
	if button.clicked then
		called = called + 1
	end
end

return {
	system.new(click_run, "click logger"):arguments({ Button }, { Foo }, GameActions),
	system.new(close_run, "close on click"):arguments({ Button, ButtonClose }, GameActions),
	system.new(change_title, "change button title"):arguments { Button, ButtonOpen },
}
