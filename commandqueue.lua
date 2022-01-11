local class = require 'ext.class'
local table = require 'ext.table'
local ffi = require 'ffi'
local cl = require 'ffi.OpenCL'
local classert = require 'cl.assert'
local classertparam = require 'cl.assertparam'
local GCWrapper = require 'ffi.gcwrapper.gcwrapper'
local GetInfo = require 'cl.getinfo'

local defaultEvent

-- here and commandqueue.lua
local function ffi_new_table(T, src)
	return ffi.new(T..'['..#src..']', src)
end

local CommandQueue = class(GetInfo(GCWrapper{
	ctype = 'cl_command_queue',
	retain = cl.clRetainCommandQueue,
	release = cl.clReleaseCommandQueue,
}))

--[[
args
	context
	device
	properties
--]]
function CommandQueue:init(args)
	assert(args, "expected args")
	self.id = classertparam('clCreateCommandQueue',
		assert(args.context, "expected context").id,
		assert(args.device, "expected device").id,
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
	event (optional) (cl.event)
--]]
function CommandQueue:enqueueReadBuffer(args)
	defaultEvent = defaultEvent or require 'cl.event'()
	classert(cl.clEnqueueReadBuffer(
		self.id,
		assert(args.buffer, "expected buffer").id,
		args.block,
		args.offset or 0,
		assert(args.size, "expected size"),
		assert(args.ptr, "expected ptr"),
		0,
		nil,
		args.event and args.event.gc.ptr or defaultEvent.gc.ptr))
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
	defaultEvent = defaultEvent or require 'cl.event'()
	classert(cl.clEnqueueWriteBuffer(
		self.id,
		assert(args.buffer, "expected buffer").id,
		args.block,
		args.offset or 0,
		assert(args.size, "expected size"),
		assert(args.ptr, "expected ptr"),
		0,
		nil,
		args.event and args.event.gc.ptr or defaultEvent.gc.ptr))
end

--[[
args:
	buffer
	pattern (optional)
	patternSize (optional)
	offset (optional)
	size (bytes)
	event (optional) cl.event
--]]
local defaultPattern = ffi.new('int[1]', 0)
function CommandQueue:enqueueFillBuffer(args)
	defaultEvent = defaultEvent or require 'cl.event'()
	local pattern = args.pattern
	local patternSize = args.patternSize
	if not pattern then
		pattern = defaultPattern
		patternSize = ffi.sizeof'int'
	end
	classert(cl.clEnqueueFillBuffer(
		self.id,
		assert(args.buffer, "expected buffer").id,
		pattern,
		patternSize,
		args.offset or 0,
		assert(args.size, "expected size"),
		0,
		nil,
		args.event and args.event.gc.ptr 
		
		-- or nil
--[[
https://github.com/thenumbernine/HydrodynamicsGPU/blob/master/src/Solver/Solver.cpp
line 24:
if you don't pass that &event pointer on my AMD Radeon then it writes garbage
CL_DEVICE_NAME:	AMD Radeon R9 M370X Compute Engine
CL_DEVICE_VENDOR:	AMD
CL_DEVICE_VERSION:	OpenCL 1.2 
CL_DRIVER_VERSION:	1.2 (Jan 11 2016 18:56:15)

...and here we are in 2021...
--]]	
		or defaultEvent.gc.ptr
	))
end

--[[
args:
	src
	dst
	srcOffset (optional)
	dstOffset (optional)
	size
--]]
function CommandQueue:enqueueCopyBuffer(args)
	defaultEvent = defaultEvent or require 'cl.event'()
	classert(cl.clEnqueueCopyBuffer(
		self.id,
		assert(args.src, "expected src").id,
		assert(args.dst, "expected dst").id,
		args.srcOffset or 0,
		args.dstOffset or 0,
		assert(args.size, "expected size"),
		0,
		nil,
		args.event and args.event.gc.ptr or defaultEvent.gc.ptr))
end

--[[
args:
	kernel
	dim (optional) if not provided then offset, globalSize, or localSize must be a table?
	offset (optional)
	globalSize
	localSize
--]]
local offset = ffi.new('size_t[3]')
local globalSize = ffi.new('size_t[3]')
local localSize = ffi.new('size_t[3]')

local function fillParam(dim, src, dst)
	if type(src) == 'number' then
		if not dim then
			dim = 1
		else
			assert(dim == 1)
		end
		dst[0] = src
	elseif type(src) == 'table' then
		if not dim then
			dim = #src
		else
			assert(dim == #src)
		end
		for i=1,dim do
			dst[i-1] = src[i]
		end
	elseif type(src) == 'cdata' then
		assert(dim)
		for i=0,dim-1 do
			dst[i] = src[i]
		end
	end
	return dim
end

--[[
args:
	dim
	offset
	globalSize
	localSize
	kernel	(optional) cl.kernel
	wait (optional) table of cl.event
	event (optional) cl.event
--]]
function CommandQueue:enqueueNDRangeKernel(args)
	defaultEvent = defaultEvent or require 'cl.event'()
	local dim = args.dim
	dim = fillParam(dim, args.offset, offset)
	dim = fillParam(dim, args.globalSize, globalSize)
	dim = fillParam(dim, args.localSize, localSize)
	local numWait = args.wait and #args.wait or 0
	local wait
	if numWait > 0 then
		wait = ffi.new('cl_event[?]', numWait)
		for i=1,numWait do
			wait[i-1] = args.wait[i].id
		end
	end
	
	classert(cl.clEnqueueNDRangeKernel(
		self.id,
		assert(args.kernel, "expected kernel").id,
		dim,
		offset,
		globalSize,
		localSize,
		numWait,
		wait,
		args.event and args.event.gc.ptr or defaultEvent.gc.ptr))
	
	-- hmm should I even use 'id' if gc.ptr[0] will be holding the same information?
	if args.event then
		args.event.id = args.event.gc.ptr[0]
	end
end

--[[
args:
	objs
--]]
function CommandQueue:enqueueAcquireGLObjects(args)
	defaultEvent = defaultEvent or require 'cl.event'()
	local objs = assert(args.objs, "expected objs")
	classert(cl.clEnqueueAcquireGLObjects(
		self.id,
		#objs,
		ffi_new_table('cl_mem', table.mapi(objs, function(obj) return obj.id end)),
		0,
		nil,
		args.event and args.event.gc.ptr or defaultEvent.gc.ptr))
end

--[[
args:
	objs
--]]
function CommandQueue:enqueueReleaseGLObjects(args)
	defaultEvent = defaultEvent or require 'cl.event'()
	local objs = assert(args.objs, "expected objs")
	classert(cl.clEnqueueReleaseGLObjects(
		self.id,
		#objs,
		ffi_new_table('cl_mem', table.mapi(objs, function(obj) return obj.id end)),
		0,
		nil,
		args.event and args.event.gc.ptr or defaultEvent.gc.ptr))
end

function CommandQueue:flush()
	cl.clFlush(self.id)
end

function CommandQueue:finish()
	cl.clFinish(self.id)
end

CommandQueue.getInfo = CommandQueue:makeGetter{
	getter = cl.clGetCommandQueueInfo,
	vars = {
		{name='CL_QUEUE_CONTEXT', type=''},
		{name='CL_QUEUE_DEVICE', type=''},
		{name='CL_QUEUE_REFERENCE_COUNT', type=''},
		{name='CL_QUEUE_PROPERTIES', type=''},
		{name='CL_QUEUE_SIZE', type=''},
		{name='CL_QUEUE_DEVICE_DEFAULT', type=''},
	},
}

return CommandQueue
