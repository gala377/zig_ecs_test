local object = {}

function object:Init()
	self.msg = "hello"
	local frame = current_frame()
	print("From script " .. self.msg .. " current frome is " .. string(frame))
end

function object:OnUpdate() end

return object
