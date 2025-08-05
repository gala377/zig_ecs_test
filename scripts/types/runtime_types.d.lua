---@meta
---@diagnostic disable: unused-local

---@class CompSelector
---@field component_hash integer
---@field metatable_name string
local CompSelector = {}

---@generic T: { [integer]: any }
---@class Query<T>
local Query = {}

---@generic T
---@param self Query<`T`>
---@return `T`?
function Query:next() end

---@param name string
---@return integer
function ComponentHash(name) end

---@diagnostic enable: unused-local
