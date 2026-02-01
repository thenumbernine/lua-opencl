require 'ext.gc'	-- add __gc to luajit
local class = require 'ext.class'

return function(cl)
	cl = class(cl)

	function cl:init(id)
		self.id = self.ctype(id)
	end

	cl.__gc = cl.release

	return cl
end
