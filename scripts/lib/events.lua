-- this part is impossible
local EventBuffer = ecs.runtime.components.EventBuffer

local function EventReader(wrapped)
	return {
		wrapped_resource = EventBuffer(wrapped),
		unwrap = function(buffer)
			local Reader = {
				pos = 0,
				buffer = buffer.events,
			}
			function Reader:next()
				if self.pos < #self.buffer then
					local res = self.buffer[self.pos]
					self.pos = self.pos + 1
					return res
				end
				return nil
			end

			function Reader:iter()
				return function()
					return self:next()
				end
			end

			return Reader
		end,
	}
end

return EventReader
