#!/usr/bin/env luajit

local function report(f)
	xpcall(f, function(err)
		io.stderr:write(err..'\n'..debug.traceback()..'\n')
	end)
end

local platforms = require 'cl.platform'.getAll()
for i,platform in ipairs(platforms) do
	print()
	print('platform '..i)
	report(function()
		platform:printInfo()
	end)

	report(function()
		local devices = platform:getDevices()
		for j,device in ipairs(devices) do
			print()
			print('-device '..j)
			report(function()
				device:printInfo()
			end)
		end

		local context = require 'cl.context'{platform=platform, devices=devices}
		print()
		print'--context'
		context:printInfo()
	end)
end
