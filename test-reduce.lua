#!/usr/bin/env luajit
--[[
reduce is having some trouble
so i'm gonna test all possible sizes
and see what's up
--]]
local range = require 'ext.range'

-- TODO get rid of default domains in env, and required size arguments
-- TODO also rename env.domain to env.defaultDomain
--  	make env:domain a function for creating domains
-- 		and move the env.domain.size code into domain.code or something?
-- TODO also rename buffer.buf to buffer.buffer ... or buffer.obj
-- 		and then rename kernel.kernel to kernel.obj
local env = require 'cl.obj.env'{size=1}

-- TODO make a range from 1 to max workgroup size, step by power of two, and include plus or minus a few 
-- then include factors of max workgroup size plus or minus a few
for size=1,257 do 
	local domain = require 'cl.obj.domain'{env=env, size=size}
	local buf = domain:buffer{
		size=2*size,
		-- data goes n, n-1, ..., 1, n+1, n+2, ..., 2*n
		-- this way a reduce any less than size will show how much less than size
		-- and a reduce any more than size will show n+ how much more than size
		data=range(size,1,-1):append(
			range(size):map(function(i) return i+size end)),
	}
	local cpu = buf:toCPU()
	local reduce = env:reduce{
		size=size,
		buffer=buf.buf,
		initValue = 'HUGE_VALF',
		op=function(x,y) return 'min('..x..', '..y..')' end,
	}
	local reduceResult = reduce()
	print('size',size,'reduce',reduceResult)
	assert(reduceResult == 1, "expected 1 but found "..reduceResult)
end
