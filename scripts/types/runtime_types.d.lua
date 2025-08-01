---@meta

---@class CompSelector
---@field component_hash integer
---@field metatable_name string
local CompSelector = {}

---@class Query: lightuserdata
local Query = {}

---@param self Query
---@return lightuserdata[]?
function Query:next() end
