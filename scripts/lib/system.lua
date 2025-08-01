local system = {}

---@param func function
function system.new(func)
	---@class SystemBuilder
	---@field queries CompSelector[][]
	---@field callback function?
	local SystemBuilder = {
		queries = {},
		callback = func,
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
