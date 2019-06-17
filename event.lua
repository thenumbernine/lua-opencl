local ffi = require 'ffi'
local cl = require 'ffi.OpenCL'
local class = require 'ext.class'
local classert = require 'cl.assert'
local Wrapper = require 'cl.wrapper'
local GetInfo = require 'cl.getinfo'

local Event = class(GetInfo(Wrapper(
	'cl_event',
	cl.clRetainEvent,
	cl.clReleaseEvent)))

function Event:wait()
	classert(cl.clWaitForEvents(1, self.gc.ptr))
end

-- static
function Event.waitForEvents(...)
	local n = select('#', ...)
	local events 
	if n > 0 then
		events = ffi.new('cl_event[?]', n) 
		for i=1,n do
			events[i-1] = select(i).id
		end
	end
	classert(cl.clWaitForEvents(n, n > 0 and events or nil))
end

Event.getInfo = Event:makeGetter{
	getter = cl.clGetEventInfo,
	vars = {
		{name='CL_EVENT_COMMAND_QUEUE', type='cl_command_queue'},
		{name='CL_EVENT_COMMAND_TYPE', type='cl_command_type'},
		{name='CL_EVENT_REFERENCE_COUNT', type='cl_uint'},
		{name='CL_EVENT_COMMAND_EXECUTION_STATUS', type='cl_int'},
		{name='CL_EVENT_CONTEXT', type='cl_context'},
	},
}

Event.getProfilingInfo = Event:makeGetter{
	getter = cl.clGetEventProfilingInfo,
	vars = {
		{name='CL_PROFILING_COMMAND_QUEUED', type='cl_ulong'},
		{name='CL_PROFILING_COMMAND_SUBMIT', type='cl_ulong'},
		{name='CL_PROFILING_COMMAND_START', type='cl_ulong'},
		{name='CL_PROFILING_COMMAND_END', type='cl_ulong'},
		{name='CL_PROFILING_COMMAND_COMPLETE', type=''},
	},
}

return Event
