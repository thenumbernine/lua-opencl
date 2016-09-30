local class = require 'ext.class'
local ffi = require 'ffi'
local cl = require 'ffi.OpenCL'
local classert = require 'cl.assert'
local classertparam = require 'cl.assertparam'
local Wrapper = require 'cl.wrapper'

-- here and commandqueue.lua
local function ffi_new_table(T, src)
	return ffi.new(T..'['..#src..']', src)
end

local CommandQueue = class(Wrapper(
	'cl_command_queue',
	cl.clRetainCommandQueue,
	cl.clReleaseCommandQueue))

--[[
args
	context
	device
	properties
--]]
function CommandQueue:init(args)
	assert(args)
	self.id = classertparam('clCreateCommandQueue',
		assert(args.context).id,
		assert(args.device).id,
		args.properties or 0)
	CommandQueue.super.init(self, self.id)
end

--[[
args:
	buffer
	block
	offset (optional) default 0
	size
	ptr
--]]
function CommandQueue:enqueueReadBuffer(args)
	classert(cl.clEnqueueReadBuffer(
		self.id,
		assert(args.buffer).id,
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
function CommandQueue:enqueueWriteBuffer(args)
	classert(cl.clEnqueueWriteBuffer(
		self.id,
		assert(args.buffer).id,
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
function CommandQueue:enqueueNDRangeKernel(args)
	assert(args.globalSize)
	assert(args.localSize, 'expected localSize')
	assert(#args.globalSize == #args.localSize)
	if args.globalOffset then fill(globalOffset, args.globalOffset) end
	fill(globalSize, args.globalSize)
	fill(localSize, args.localSize)
	classert(cl.clEnqueueNDRangeKernel(
		self.id,
		assert(args.kernel).id,
		#args.globalSize,
		globalOffset,
		globalSize,
		localSize,
		0,
		nil,
		nil))
end

--[[
args:
	objs
--]]
function CommandQueue:enqueueAcquireGLObjects(args)
	local objs = assert(args.objs)
	classert(cl.clEnqueueAcquireGLObjects(
		self.id,
		#objs,
		ffi_new_table('cl_mem', table.map(objs, function(obj) return obj.id end)),
		0,
		nil,
		nil))
end

--[[
args:
	objs
--]]
function CommandQueue:enqueueReleaseGLObjects(args)
	local objs = assert(args.objs)
	classert(cl.clEnqueueReleaseGLObjects(
		self.id,
		#objs,
		ffi_new_table('cl_mem', table.map(objs, function(obj) return obj.id end)),
		0,
		nil,
		nil))
end

function CommandQueue:finish()
	cl.clFinish(self.id)
end

return CommandQueue
