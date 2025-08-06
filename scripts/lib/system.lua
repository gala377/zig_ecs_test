local system = {}

---@param func function
---@param name? string
---@return SystemBuilder
function system.new(func, name)
	---@class SystemBuilder
	---@field queries CompSelector[][]
	---@field callback function?
	---@field name string?
	local SystemBuilder = {
		queries = {},
		callback = func,
		name = name,
	}
	function SystemBuilder:query(...)
		local toTable = { ... }
		local asIds = {}
		for _, value in ipairs(toTable) do
			asIds[#asIds + 1] = value
		end
		self.queries[#self.queries + 1] = asIds
		return self
	end

	return SystemBuilder
end

return system
