local module = {}

---@generic T
---@param iterator Query<T>
---@return fun(): T?
function module.query(iterator)
	return function()
		local next = iterator:next()
		if next == nil then
			return nil
		else
			return table.unpack(next)
		end
	end
end

---@generic T
---@param iterator Query<T>
---@return T, boolean
function module.single(iterator)
	local res = iterator:next()
	if res == nil then
		return {}, false
	end
	if iterator:next() ~= nil then
		return nil, false
	end
	return res, true
end

return module
