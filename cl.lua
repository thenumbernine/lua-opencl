--[[
shortcut method
takes the first platform and device
creates a context and commands
args:
	device = platform:getDevices arguments
	context = Context() arguments
	commands = Commands() arguments
	program (optional) Program() arguments (which is built upon creation)
--]]
local function quickstart(args)
	local table = require 'ext.table'
	local platform, device = require 'cl.platform'.getFirst(args.device)
	local context = require 'cl.context'(table({platform=platform, device=device}, args.context))
	local commands = require 'cl.commands'(table({context=context, device=device}, args.commands))
	local program = args.program and require 'cl.program'(table({context=context, devices={device}}, args.program)) or nil
	return platform, device, context, commands, program
end

return quickstart
