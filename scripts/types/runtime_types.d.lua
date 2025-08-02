---@meta

---@class CompSelector
---@field component_hash integer
---@field metatable_name string
local CompSelector = {}

---@generic T
---@class Query<T>
local Query = {}

---@generic T
---@param self Query<T>
---@return T?
function Query:next() end
