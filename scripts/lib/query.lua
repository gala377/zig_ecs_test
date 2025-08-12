local module = {}

---@generic T1, T2, T3, T4, T5, T6, T7, T8, T9, T10
---@param iterator Query<[
--- `T1`,
--- `T2`?,
--- `T3`?,
--- `T4`?,
--- `T5`?,
--- `T6`?,
--- `T7`?,
--- `T8`?,
--- `T9`?,
--- `T10`?,
---]>
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
---@param iterator Query<[`T1`, `T2`?, `T3`?, `T4`?, `T5`?, `T6`?, `T7`?, `T8`?, `T9`?, `T10`?]>
---@return T1?, T2, T3, T4, T5, T6, T7, T8, T9, T10
function module.single(iterator)
	---@diagnostic disable: missing-return-value
	local res = iterator:next()
	if res == nil then
		return nil
	end
	local next = iterator:next()
	if next ~= nil then
		return nil
	end
	return table.unpack(res)
	---@diagnostic enable: missing-return-value
end

return module
