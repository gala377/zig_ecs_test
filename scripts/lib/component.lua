--- Returns a file path of the script that called the
---`component` function.
---@return string
local function script_path()
	return debug.getinfo(3, "S").short_src
end

---@generic T
---@alias LuaComp<T> `T` & { component_hash: string }

---@generic T: table
---@param name string file unique name of the component
---@param init? `T` initial value for the component
---@return `T` & { component_hash: string }
return function(name, init)
	local ret = init or {}
	local fq_name = script_path() .. name .. "$lua"
	ret.component_hash = ComponentHash(fq_name)
	return ret
end
