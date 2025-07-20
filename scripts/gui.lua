local state = {}

function state:init()
	return {
		"spawn",
		{
			"raygui:button",
			title = "Close application",
			pos = { 0, 0 },
			size = { 100, 100 },
			callback = self.onClicked,
		},
	}
end

function state:onClicked()
	return {
		"app:close",
	}
end

return state
