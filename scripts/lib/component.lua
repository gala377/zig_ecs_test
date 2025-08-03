--- Returns a file path of the script that called the
---`component` function.
---@return string
local function script_path()
	return debug.getinfo(3, "S").short_src
end

---@generic T
---@alias LuaComp<T> `T` & { component_hash: string }

---@generic T: table
---@param init? `T` initial value for the component
---@return `T` & { component_hash: string }
return function(init)
	local ret = init or {}
	ret.component_hash = script_path() .. ".component"
	return ret
end
