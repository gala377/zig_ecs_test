local Component = require("scripts.path")

local MyComp = Component({
	name = "hello",
	x = 1,
	y = 2,
})

print(MyComp.component_hash)
