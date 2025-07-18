local state = {}

function state.draw()
	return {
		"gui",
		{
			"button",
			"Close application",
			onClick = function()
				return { "command", "app:close" }
			end,
		},
	}
end

return state
