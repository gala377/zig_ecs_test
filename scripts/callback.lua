---@alias Button ecs.imgui.components.Button
---@alias GameActions ecs.game.GameActions

local components = require("scripts.generated")
local Button = components.ecs.imgui.components.Button
local GameActions = components.ecs.game.GameActions

---@class CompSelector
---@field component_hash integer
---@field metatable_name string
---@field is_resource boolean
local CompSelector = {}

local function copy(t)
	local res = {}
	for key, value in pairs(t) do
		res[key] = value
	end
	return res
end

local system = {}
function system.new()
	---@class SystemBuilder
	---@field queries CompSelector[][]
	---@field callback function?
	local SystemBuilder = {
		queries = {},
		callback = nil,
	}
	function SystemBuilder:query(...)
		local toTable = { ... }
		local asIds = {}
		for _, value in ipairs(toTable) do
			local copied = copy(value)
			copied.is_resource = false
			asIds[#asIds + 1] = copied
		end
		self.queries[#self.queries + 1] = asIds
		return self
	end

	function SystemBuilder:resource(t)
		local copied = copy(t)
		copied.is_resource = true
		self.queries[#self.queries + 1] = copied
		return self
	end

	function SystemBuilder:call(func)
		if type(func) == "table" then
			self.callback = func[0]
		else
			self.callback = func
		end
	end
	return SystemBuilder
end

return system.new():query(Button, GameActions):resource(Button):call(
	---@param iter { [1]: Button, [2]: GameActions }
	---@param button Button
	function(iter, button) end
)
