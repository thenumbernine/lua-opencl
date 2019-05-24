#!/usr/bin/env luajit

local table = require 'ext.table'
local platforms = require 'cl.platform'.getAll()
for i,platform in ipairs(platforms) do
	print()
	print('platform '..i)
	platform:printInfo()

	local devices = platform:getDevices()
	for i,device in ipairs(devices) do
		print()
		print(' device '..i)
		device:printInfo()
		
		local context = require 'cl.context'(table({platform=platform, device=device}))
		print()
		print'  context'
		context:printInfo()
	end
end
