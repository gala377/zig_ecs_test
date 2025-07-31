---@alias Button ecs.imgui.components.Button

---@param button Button
return function(button)
	print("visibile=" .. tostring(button.visible))
	if button.visible then
		button.visible = false
	end
end
