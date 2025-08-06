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

---@generic T
---@class Slice: { [integer]: T }
local Slice = {}

---@generic T
---@param self Slice<T>
---@return T[]
function Slice:totable() end

---@generic T
---@param self Slice<T>
---@return integer
function Slice:len() end

---@diagnostic enable: unused-local
