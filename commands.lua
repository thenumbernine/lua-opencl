local class = require 'ext.class'
local ffi = require 'ffi'
local cl = require 'ffi.OpenCL'
local classert = require 'cl.assert'

local Commands = class()

--[[
args
	context
	device
	properties
--]]
function Commands:init(args)
	assert(args)
	local err = ffi.new('cl_uint[1]',0)
	self.obj = cl.clCreateCommandQueue(
		assert(args.context).obj,
		assert(args.device).obj,
		args.properties or 0,
		err)
	classert(err[0])
end

--[[
args:
	buffer
	block
	offset (optional) default 0
	size
	ptr
--]]
function Commands:enqueueReadBuffer(args)
	classert(cl.clEnqueueReadBuffer(
		self.obj,
		assert(args.buffer).obj,
		args.block,
		args.offset or 0,
		assert(args.size),
		assert(args.ptr),
		0,
		nil,
		nil))
end

--[[
args:
	buffer
	block
	offset (optional) default 0
	size
	ptr
--]]
function Commands:enqueueWriteBuffer(args)
	classert(cl.clEnqueueWriteBuffer(
		self.obj,
		assert(args.buffer).obj,
		args.block,
		args.offset or 0,
		assert(args.size),
		assert(args.ptr),
		0,
		nil,
		nil))
end

--[[
args:
	kernel
	offset (optional)
	globalSize
	localSize
--]]
local globalOffset = ffi.new('size_t[3]')
local globalSize = ffi.new('size_t[3]')
local localSize = ffi.new('size_t[3]')
local function fill(dst, src)
	local n = #src
	assert(n >= 1 and n <= 3)
	for i=1,n do
		dst[i-1] = src[i]
	end
end
function Commands:enqueueNDRangeKernel(args)
	assert(args.globalSize)
	assert(args.localSize)
	assert(#args.globalSize == #args.localSize)
	if args.globalOffset then fill(globalOffset, args.globalOffset) end
	fill(globalSize, args.globalSize)
	fill(localSize, args.localSize)
	classert(cl.clEnqueueNDRangeKernel(
		self.obj,
		assert(args.kernel).obj,
		#args.globalSize,
		globalOffset,
		globalSize,
		localSize,
		0,
		nil,
		nil))
end

function Commands:finish()
	cl.clFinish(self.obj)
end

return Commands
