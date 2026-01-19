---@diagnostic disable: missing-return-value
local module = {}

---@generic T1, T2, T3, T4, T5, T6, T7, T8, T9, T10
---@alias Arg_Iter {
--- [1]: T1,
--- [2]?: T2,
--- [3]?: T3,
--- [4]?: T4,
--- [5]?: T5,
--- [6]?: T6,
--- [7]?: T7,
--- [8]?: T8,
--- [9]?: T9,
--- [10]?: T10,
---}
---@param iterator Query<Arg_Iter>
---@return fun(): T1?, T2, T3, T4, T5, T6, T7, T8, T9, T10
function module.iter(iterator)
	return function()
		local next = iterator:next()
		if next == nil then
			return nil
		else
			return table.unpack(next)
		end
	end
end

---@generic T1, T2, T3, T4, T5, T6, T7, T8, T9, T10
---@param iterator Query<Arg_Iter>
---@return T1?, T2, T3, T4, T5, T6, T7, T8, T9, T10
function module.single(iterator)
	local res = iterator:next()
	if res == nil then
		return nil
	end
	local next = iterator:next()
	if next ~= nil then
		return nil
	end
	return table.unpack(res)
end

---@generic T1, T2, T3, T4, T5, T6, T7, T8, T9, T10
---@param iterator Query<Arg_Iter>
---@return T1, T2, T3, T4, T5, T6, T7, T8, T9, T10
function module.assertSingle(iterator)
	local res = iterator:next()
	if res == nil then
		return nil
	end
	local next = iterator:next()
	if next ~= nil then
		return nil
	end
	return table.unpack(res)
end

return module
