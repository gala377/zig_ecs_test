-- TODO: WORK IN PROGRESS
-- I am trying to expose event readers and event writers to lua
-- but i am not sure how as they depend on generics
--
-- well this migth be possible if we express the fields as
-- my.namespace.inner["EventReader(usize)"]
-- we dealt with this in bevy
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
