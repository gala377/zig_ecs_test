---@param iterator Query
---@return fun(): lightuserdata[]?
local function query(iterator)
	return function()
		return iterator:next()
	end
end

---@param iterator Query
---@return lightuserdata[], boolean
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
