#!/usr/bin/env luajit
local range = require 'ext.range'
local CLEnv = require 'cl.obj.env'

local sizes = {{64}, {8,8}, {4,4,4}}
--local sizes = {{8}, {2,4}, {2,2,2}}


for dim,size in ipairs(sizes) do
	print('test '..dim..'D kernel')

	local env = CLEnv{
		verbose = true,
		useGLSharing = false,
		getPlatform = CLEnv.getPlatformFromCmdLine(...),
		getDevices = CLEnv.getDevicesFromCmdLine(...),
		deviceType = CLEnv.getDeviceTypeFromCmdLine(...),
		size = size,
	} 
	local a = env:buffer{name='a', type='real', data=range(env.base.volume)}
	local b = env:buffer{name='b', type='real', data=range(env.base.volume)}
	local c = env:buffer{name='c', type='real'}
	env:kernel{
		-- testing varying-shaped domains
		domain = env:domain{dim=1, size=sizes[1][1], device=env.devices[1]},
		argsOut = {c},
		argsIn = {a, b},
		body='c[index] = a[index] * b[index];',
	}()

	local aMem = a:toCPU()
	local bMem = b:toCPU()
	local cMem = c:toCPU()
	for i=0,env.base.volume-1 do
		io.write(' '..aMem[i]..' * '..bMem[i]..' = '..cMem[i])
	end
	print()

	print('test '..dim..'D reduce')

	local sum = env:reduce{
		buffer = c.obj,
		op = function(x,y) return x .. '+' .. y end,
	}
	local val = sum()
	print('sum 1..'..sizes[1][1]..' = '..val)
	print('test '..dim..'D reduce buffer subset')

	local sum = env:reduce{
		buffer = c.obj,
		count = sizes[1][1]/2,
		op = function(x,y) return x .. '+' .. y end,
	}
	local val = sum()
	print('sum 1..'..(sizes[1][1]/2)..' = '..val)

	local sum = env:reduce{
		buffer = c.obj,
		op = function(x,y) return x .. '+' .. y end,
	}
	local val = sum(nil, sizes[1][1]/2)
	print('sum 1..'..(sizes[1][1]/2)..' = '..val)
	print('test '..dim..'D reduce buffer subset')
	collectgarbage()	-- see if all the cl objs get freed here
end

print'done'
