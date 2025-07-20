local state = {}

function state.new() end

function state:init()
	return {
		"spawn",
		{
			"raygui:button",
			title = "Close application",
			position = { 0, 0 },
			size = { 100, 100 },
			onCall = self.onClicked,
		},
	}
end

function state:onClicked()
	return {
		"app:close",
	}
end

return state
