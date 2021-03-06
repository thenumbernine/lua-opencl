#!/usr/bin/env luajit
local range = require 'ext.range'
local table = require 'ext.table'
local CLEnv = require 'cl.obj.env'

-- TODO env.size optional?  for no env.base?  but env:kernel needs env.base ...
local env = CLEnv{
	getPlatform = CLEnv.getPlatformFromCmdLine(...),
	getDevices = CLEnv.getDevicesFromCmdLine(...),
}

local maxWorkGroupSize = tonumber(env.devices[1]:getInfo'CL_DEVICE_MAX_WORK_GROUP_SIZE')
local values = table()
local nbhd = 3
do
	-- make a range from 1 to max workgroup size, step by power of two, and include plus or minus a few 
	local i = 1
	while i <= maxWorkGroupSize do
		for ofs=i-nbhd,i+nbhd do
			if ofs > 0 then
				values[ofs] = true
			end
		end
		i = i * 2
	end
	
	-- then include factors of max workgroup size plus or minus a few
	for po4=1,3 do
		local maxFactor = 4^po4
		while i < maxWorkGroupSize*maxFactor do
			for ofs=i-nbhd,i+nbhd do
				values[ofs] = true
			end
			i = i + maxWorkGroupSize
		end
	end	
	
	values = values:keys():sort()
end

print('testing reduce on ranges: '..values:concat', ')

for _,size in ipairs(values) do
	local buf = env:domain{size=size}:buffer{
		count=2*size,
		-- data goes n, n-1, ..., 1, n+1, n+2, ..., 2*n
		-- this way a reduce any less than size will show how much less than size
		-- and a reduce any more than size will show n+ how much more than size
		data=range(size,1,-1)
			:append(range(size):mapi(function(i) return i+size end)),
	}
	local cpu = buf:toCPU()
	local reduce = env:reduce{
		count = size,
		buffer = buf.obj,
		initValue = 'HUGE_VALF',
		op = function(x,y) return 'min('..x..', '..y..')' end,
	}
	local reduceResult = reduce()
	print('size',size,'reduce',reduceResult)
	assert(reduceResult == 1, "expected 1 but found "..reduceResult)
end
