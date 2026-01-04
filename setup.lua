--[[
shortcut method
takes the first platform and device
creates a context and command queue
args:
	device = platform:getDevices() arguments
	context = Context() arguments
	queue = CommandQueue() arguments
	program (optional) Program() arguments (which is built upon creation)
--]]
local function quickstart(args)
	local table = require 'ext.table'
	local platforms = require 'cl.platform'.getAll()
--DEBUG:for i,platform in ipairs(platforms) do
--DEBUG:	print()
--DEBUG:	print('platform '..i)
--DEBUG:	platform:printInfo()
--DEBUG:end
	local platform = assert(platforms[1], "failed to find a platform")

	local devices = platform:getDevices(args.device)
--DEBUG:for i,device in ipairs(devices) do
--DEBUG:	print()
--DEBUG:	print('device '..i)
--DEBUG:	device:printInfo()
--DEBUG:end

	local context = require 'cl.context'(table({platform=platform, devices=devices}, args.context))
--DEBUG:print()
--DEBUG:print'context'
--DEBUG:context:printInfo()

	local device = assert(devices[1], "failed to find a device")
	local queue
	local program
	if device then
		queue = require 'cl.commandqueue'(table({context=context, device=device}, args.queue))
		program = args.program and require 'cl.program'(table({context=context, devices=devices}, args.program)) or nil
	end
	return platform, devices, context, queue, program
end

return quickstart
