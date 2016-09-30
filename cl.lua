--[[
shortcut method
takes the first platform and device
creates a context and command queue
args:
	device = platform:getDevices arguments
	context = Context() arguments
	queue = CommandQueue() arguments
	program (optional) Program() arguments (which is built upon creation)
--]]
local function quickstart(args)
	local table = require 'ext.table'
	local platform, device = require 'cl.platform'.getFirst(args.device)
	local context = require 'cl.context'(table({platform=platform, device=device}, args.context))
	local queue = require 'cl.commandqueue'(table({context=context, device=device}, args.queue))
	local program = args.program and require 'cl.program'(table({context=context, devices={device}}, args.program)) or nil
	return platform, device, context, queue, program
end

return quickstart
