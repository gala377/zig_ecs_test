local query = require("scripts.lib.query")

local system = {}

---@param func function
---@param name? string
---@return SystemBuilder
function system.new(func, name)
	---@class SystemBuilder
	---@field queries CompSelector[][]
	---@field callback function
	---@field name string?
	local SystemBuilder = {
		queries = {},
		callback = func,
		name = name,
	}

	function SystemBuilder:arguments(...)
		local args = { ... }
		local resource_indexes = {}
		local queries = {}
		for i, value in ipairs(args) do
			if value.component_hash ~= nil then
				resource_indexes[#resource_indexes + 1] = i
				queries[#queries + 1] = { value }
			else
				local copy = {}
				for _, comp in ipairs(value) do
					copy[#copy + 1] = comp
				end
				queries[#queries + 1] = copy
			end
		end
		self.queries = queries
		if #resource_indexes > 0 then
			-- only wrap when callback when there are resources to unwrap
			local callback = self.callback
			self.callback = function(...)
				local callback_args = { ... }
				for _, index in ipairs(resource_indexes) do
					callback_args[index] = query.single(callback_args[index])
				end
				return callback(table.unpack(callback_args))
			end
		end
		return self
	end
	return SystemBuilder
end

return system
