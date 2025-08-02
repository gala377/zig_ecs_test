---@generic T
---@param iterator Query<T>
---@return fun(): T?
local function query(iterator)
	return function()
		return iterator:next()
	end
end

---@generic T
---@param iterator Query<T>
---@return T, boolean
local function single(iterator)
	local res = iterator:next()
	if res == nil then
		return {}, false
	end
	if iterator:next() ~= nil then
		return {}, false
	end
	return res, true
end

return {
	query = query,
	signle = single,
}
