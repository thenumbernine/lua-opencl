local ffi = require 'ffi'
local cl = require 'ffi.req' 'OpenCL'
local classert = require 'cl.assert'
local GCWrapper = require 'cl.gcwrapper'
local GetInfo = require 'cl.getinfo'

local Event = GetInfo(GCWrapper{
	ctype = 'cl_event',
	retain = function(self) return cl.clRetainEvent(self.id) end,
	release = function(self) return cl.clReleaseEvent(self.id) end,
}):subclass()

function Event:init(...)
	self.ptr = ffi.new(self.ctype..'[1]')	-- here cuz in commandqueue it is used so often
	self.id = self.ptr[0]	-- erm does it matter?
end

function Event:wait()
	classert(cl.clWaitForEvents(1, self.id))
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
		-- 1.0:
		{name='CL_EVENT_COMMAND_QUEUE', type='cl_command_queue'},
		{name='CL_EVENT_COMMAND_TYPE', type='cl_command_type'},
		{name='CL_EVENT_REFERENCE_COUNT', type='cl_uint'},
		{name='CL_EVENT_COMMAND_EXECUTION_STATUS', type='cl_int'},
		-- 1.1
		{name='CL_EVENT_CONTEXT', type='cl_context'},
	},
}

Event.getProfilingInfo = Event:makeGetter{
	getter = cl.clGetEventProfilingInfo,
	vars = {
		-- 1.0
		{name='CL_PROFILING_COMMAND_QUEUED', type='cl_ulong'},
		{name='CL_PROFILING_COMMAND_SUBMIT', type='cl_ulong'},
		{name='CL_PROFILING_COMMAND_START', type='cl_ulong'},
		{name='CL_PROFILING_COMMAND_END', type='cl_ulong'},
		-- 2.0
		{name='CL_PROFILING_COMMAND_COMPLETE', type='cl_ulong'},
	},
}

return Event
