#!/usr/bin/env luajit
local range = require 'ext.range'

local sizes = {{64}, {8,8}, {4,4,4}}
--local sizes = {{8}, {2,4}, {2,2,2}}

for dim,size in ipairs(sizes) do
	print('test '..dim..'D kernel')

	local env = require 'cl.obj.env'{size=size} 
	local a = env:buffer{name='a', type='real', data=range(env.domain.volume)}
	local b = env:buffer{name='b', type='real', data=range(env.domain.volume)}
	local c = env:buffer{name='c', type='real'}
	env:kernel{
		-- testing varying-shaped domains
		domain = require 'cl.obj.domain'{env=env, dim=1, size=sizes[1][1]},
		argsOut = {c},
		argsIn = {a,b},
		body='c[index] = a[index] * b[index];',
	}()

	local aMem = a:toCPU()
	local bMem = b:toCPU()
	local cMem = c:toCPU()
	for i=0,env.domain.volume-1 do
		io.write(' '..aMem[i]..' * '..bMem[i]..' = '..cMem[i])
	end
	print()

	print('test '..dim..'D reduce')

	local sum = env:reduce{
		buffer = c.buf,
		op = function(x,y) return x .. '+' .. y end,
	}
	print('sum 1..'..sizes[1][1]..' = '..sum())

	print('test '..dim..'D reduce buffer subset')

	local sum = env:reduce{
		buffer = c.buf,
		size = sizes[1][1]/2,
		op = function(x,y) return x .. '+' .. y end,
	}
	print('sum 1..'..(sizes[1][1]/2)..' = '..sum())
end
