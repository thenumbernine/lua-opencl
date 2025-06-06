#!/usr/bin/env luajit
local range = require 'ext.range'
local assert = require 'ext.assert'
local class = require 'ext.class'
local table = require 'ext.table'
local CLEnv = require 'cl.obj.env'

--local sizes = {{64}, {8,8}, {4,4,4}}
--local sizes = {{8}, {2,4}, {2,2,2}}
local sizes = {{64}}


-- hold a buffer per device
local MultiBuffer = class()

function MultiBuffer:init(args)
	local env = assert.index(args, 'env')
	self.env = env

	self.buffers = env.blocks:mapi(function(block,i)
		local blockArgs = table(args)
		if blockArgs.data then
			if type(blockArgs.data) == 'table' then
				assert.len(blockArgs.data, block.domain.volume)
				local startindex = math.floor(block.domain.volume * (i-1) / #env.blocks)
				local endindex = math.floor(block.domain.volume * i / #env.blocks)
				blockArgs.data = table.sub(blockArgs.data, startindex+1, endindex+1)
			else
				error("not supported yet")
			end
		end
		-- if blockArgs.domain and blockArgs.domain matches with env.base domain ...
		blockArgs.domain = block.domain
		return env:buffer(blockArgs)
	end)
end


local MultiEnv = class(CLEnv)

function MultiEnv:init(args)
	MultiEnv.super.init(self, args)

	if args.size then
		local size = args.size
		local dim = self.dim
		local min = table{0}:rep(dim)
		local max = table(size)
		local n = #self.devices
		self.blocks = range(n):mapi(function(i)
			local device = self.devices[i]
			local blockmin = table(min)
			local blockmax = table(max)
			-- interpolate along largest dimension #
			-- so that memory is contiguous
			blockmin[dim] = math.floor(i/n*size[dim])
			blockmax[dim] = math.floor((i+1)/n*size[dim])
			local blocksize = table(size)
			blocksize[dim] = blockmax[dim] - blockmin[dim]
			return {
				min = blockmin,
				max = blockmax,
				domain = self:domain{
					size = blocksize,
					dim = dim,
					verbose = args.verbose,
					device = device,
				}
			}
		end)
	end
end

function MultiEnv:multiBuffer(args)
	return MultiBuffer(table(args, {env=self}))
end


for dim,size in ipairs(sizes) do
	print('test '..dim..'D kernel')

	local env = MultiEnv{
		verbose = true,
		getPlatform = CLEnv.getPlatformFromCmdLine(...),
		getDevices = CLEnv.getDevicesFromCmdLine(...),
		size = size,
	}

	print('#devices', #env.devices)

	-- need one domain per device for multi devices

	local a = env:multiBuffer{name='a', data=range(env.base.volume)}
	local b = env:multiBuffer{name='b', data=range(env.base.volume)}
	local c = env:multiBuffer{name='c'}

	env:multiKernel{
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
	print('sum 1..'..sizes[1][1]..' = '..sum())

	print('test '..dim..'D reduce buffer subset')

	sum = env:reduce{
		buffer = c.obj,
		count = sizes[1][1]/2,
		op = function(x,y) return x .. '+' .. y end,
	}
	print('sum 1..'..(sizes[1][1]/2)..' = '..sum())
end
