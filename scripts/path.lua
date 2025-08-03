local function script_path()
	return debug.getinfo(3, "S").short_src
end

---@param init ?table initial value for the component
return function(init)
	local ret = init or {}
	ret.component_hash = script_path() .. ".component"
	return ret
end
