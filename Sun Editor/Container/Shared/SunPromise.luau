

return function(env, libraries)
	local game, task, os, math, Random, coroutine, type, warn =
		env.game, env.task, env.os, env.math, env.Random, env.coroutine, env.type, env.warn
	local MSG = {
		notAList = "%s expects an array of promises",
		notAPromise = "%s found a non-promise at index %s",
		notAHandler = "%s expects a function",
	}

	local WEAK_KEYS = { __mode = "k" }

	local function callable(value)
		local kind = type(value)

		if kind == "function" then
			return true
		end

		if kind == "table" then
			local meta = getmetatable(value)
			return type(meta) == "table" and type(rawget(meta, "__call")) == "function"
		end

		return false
	end

	local function sealedEnum(label, names)
		local members = {}

		for _, name in ipairs(names) do
			members[name] = name
		end

		return setmetatable(members, {
			__index = function(_, key)
				error(string.format("'%s' is not a member of %s", tostring(key), label), 2)
			end,
			__newindex = function()
				error(string.format("%s cannot be extended", label), 2)
			end,
		})
	end

	local Status =
		sealedEnum("SunPromise.Status", { "Started", "Resolved", "Rejected", "Cancelled" })

	local Error = {
		Kind = sealedEnum("SunPromise.Error.Kind", {
			"ExecutionError",
			"AlreadyCancelled",
			"NotResolvedInTime",
			"TimedOut",
		}),
	}
	Error.__index = Error

	function Error.new(options, parent)
		options = options or {}

		return setmetatable({
			error = if options.error ~= nil
				then tostring(options.error)
				else "[no error text was provided]",
			trace = options.trace,
			context = options.context,
			kind = options.kind,
			parent = parent,
			createdTick = os.clock(),
			createdTrace = debug.traceback(),
		}, Error)
	end

	function Error.is(value)
		if type(value) ~= "table" then
			return false
		end

		local meta = getmetatable(value)

		return type(meta) == "table"
			and rawget(value, "error") ~= nil
			and type(rawget(meta, "extend")) == "function"
	end

	function Error.isKind(value, kind)
		assert(kind ~= nil, "SunPromise.Error.isKind needs a kind to compare against")

		return Error.is(value) and value.kind == kind
	end

	function Error:extend(options)
		options = options or {}
		options.kind = options.kind or self.kind

		return Error.new(options, self)
	end

	function Error:getErrorChain()
		local chain = {}
		local node = self

		while node do
			table.insert(chain, node)
			node = node.parent
		end

		return chain
	end

	function Error:__tostring()
		local lines = { string.format("[SunPromise.Error | %s]", self.kind or "?") }

		for _, link in ipairs(self:getErrorChain()) do
			table.insert(lines, table.concat({ link.trace or link.error, link.context }, "\n"))
		end

		return table.concat(lines, "\n")
	end

	local function capture(ok, ...)
		return ok, table.pack(...)
	end

	local function spill(promise)
		local result = promise._result
		return table.unpack(result, 1, result.n)
	end

	local function trap(origin)
		assert(origin ~= nil, "an origin trace is required")

		return function(err)
			if type(err) == "table" then
				return err
			end

			return Error.new({
				error = err,
				kind = Error.Kind.ExecutionError,
				trace = debug.traceback(tostring(err), 2),
				context = "SunPromise created at:\n\n" .. origin,
			})
		end
	end

	local function guarded(origin, fn, ...)
		return capture(xpcall(fn, trap(origin), ...))
	end

	local function relay(origin, handler, resolve, reject)
		return function(...)
			local ok, out = guarded(origin, handler, ...)

			if ok then
				resolve(table.unpack(out, 1, out.n))
			else
				reject(out[1])
			end
		end
	end

	local function flush(queue, ...)
		for _, fn in ipairs(queue) do
			coroutine.wrap(fn)(...)
		end
	end

	local function cancelAll(list)
		for _, promise in ipairs(list) do
			promise:cancel()
		end
	end

	local SunPromise = {
		Error = Error,
		Status = Status,
		_clock = os.clock,
		_pulse = game:GetService("RunService").Heartbeat,
		_rejectionListeners = {},
	}
	SunPromise.prototype = {}
	SunPromise.__index = SunPromise.prototype

	local function expectList(value, label, level)
		if type(value) ~= "table" then
			error(string.format(MSG.notAList, label), level + 1)
		end
	end

	local function expectPromises(list, label, level)
		for index, item in pairs(list) do
			if not SunPromise.is(item) then
				error(string.format(MSG.notAPromise, label, tostring(index)), level + 1)
			end
		end
	end

	function SunPromise._new(origin, executor, upstream)
		if upstream ~= nil and not SunPromise.is(upstream) then
			error("SunPromise.new expects its parent to be a promise or nil", 2)
		end

		local self = setmetatable({
			_runner = nil,
			_origin = origin,
			_state = Status.Started,
			_result = nil,
			_unobserved = true,
			_onResolve = {},
			_onReject = {},
			_onSettle = {},
			_cancelHook = nil,
			_upstream = upstream,
			_downstream = setmetatable({}, WEAK_KEYS),
		}, SunPromise)

		if upstream and upstream._state == Status.Started then
			upstream._downstream[self] = true
		end

		local function resolve(...)
			self:_resolve(...)
		end

		local function reject(...)
			self:_reject(...)
		end

		local function onCancel(hook)
			if hook then
				if self._state == Status.Cancelled then
					hook()
				else
					self._cancelHook = hook
				end
			end

			return self._state == Status.Cancelled
		end

		self._runner = coroutine.create(function()
			local ok, out = guarded(self._origin, executor, resolve, reject, onCancel)

			if not ok then
				reject(out[1])
			end
		end)

		task.spawn(self._runner)

		return self
	end

	function SunPromise.new(executor)
		return SunPromise._new(debug.traceback(nil, 2), executor)
	end

	function SunPromise:__tostring()
		return string.format("SunPromise(%s)", self._state)
	end

	function SunPromise.defer(executor)
		local origin = debug.traceback(nil, 2)

		return SunPromise._new(origin, function(resolve, reject, onCancel)
			task.defer(function()
				local ok, out = guarded(origin, executor, resolve, reject, onCancel)

				if not ok then
					reject(out[1])
				end
			end)
		end)
	end

	SunPromise.async = SunPromise.defer

	function SunPromise.resolve(...)
		local values = table.pack(...)

		return SunPromise._new(debug.traceback(nil, 2), function(resolve)
			resolve(table.unpack(values, 1, values.n))
		end)
	end

	function SunPromise.reject(...)
		local values = table.pack(...)

		return SunPromise._new(debug.traceback(nil, 2), function(_, reject)
			reject(table.unpack(values, 1, values.n))
		end)
	end

	function SunPromise._try(origin, callback, ...)
		local args = table.pack(...)

		return SunPromise._new(origin, function(resolve)
			resolve(callback(table.unpack(args, 1, args.n)))
		end)
	end

	function SunPromise.try(callback, ...)
		return SunPromise._try(debug.traceback(nil, 2), callback, ...)
	end

	function SunPromise._all(origin, promises, quota)
		expectList(promises, "SunPromise.all", 3)
		expectPromises(promises, "SunPromise.all", 3)

		if #promises == 0 or quota == 0 then
			return SunPromise.resolve({})
		end

		return SunPromise._new(origin, function(resolve, reject, onCancel)
			local collected = {}
			local children = {}

			local fulfilled = 0
			local failures = 0
			local finished = false

			local function onFulfilled(index, ...)
				if finished then
					return
				end

				fulfilled += 1

				if quota == nil then
					collected[index] = ...
				else
					collected[fulfilled] = ...
				end

				if fulfilled >= (quota or #promises) then
					finished = true
					resolve(collected)
					cancelAll(children)
				end
			end

			onCancel(function()
				cancelAll(children)
			end)

			for index, promise in ipairs(promises) do
				children[index] = promise:andThen(function(...)
					onFulfilled(index, ...)
				end, function(...)
					failures += 1

					if quota == nil or #promises - failures < quota then
						cancelAll(children)
						finished = true

						reject(...)
					end
				end)
			end

			if finished then
				cancelAll(children)
			end
		end)
	end

	function SunPromise.all(promises)
		return SunPromise._all(debug.traceback(nil, 2), promises)
	end

	function SunPromise.fold(list, reducer, initial)
		assert(type(list) == "table", "SunPromise.fold expects a table as argument #1")
		assert(callable(reducer), "SunPromise.fold expects a function as argument #2")

		local running = SunPromise.resolve(initial)

		return SunPromise.each(list, function(item, index)
			running = running:andThen(function(previous)
				return reducer(previous, item, index)
			end)
		end):andThen(function()
			return running
		end)
	end

	function SunPromise.some(promises, count)
		assert(type(count) == "number", "SunPromise.some expects a number as argument #2")

		return SunPromise._all(debug.traceback(nil, 2), promises, count)
	end

	function SunPromise.any(promises)
		return SunPromise._all(debug.traceback(nil, 2), promises, 1):andThen(function(values)
			return values[1]
		end)
	end

	function SunPromise.allSettled(promises)
		expectList(promises, "SunPromise.allSettled", 2)
		expectPromises(promises, "SunPromise.allSettled", 2)

		if #promises == 0 then
			return SunPromise.resolve({})
		end

		return SunPromise._new(debug.traceback(nil, 2), function(resolve, _, onCancel)
			local outcomes = {}
			local children = {}
			local settled = 0

			onCancel(function()
				cancelAll(children)
			end)

			for index, promise in ipairs(promises) do
				children[index] = promise:finally(function(...)
					settled += 1
					outcomes[index] = ...

					if settled >= #promises then
						resolve(outcomes)
					end
				end)
			end
		end)
	end

	function SunPromise.race(promises)
		expectList(promises, "SunPromise.race", 2)
		expectPromises(promises, "SunPromise.race", 2)

		return SunPromise._new(debug.traceback(nil, 2), function(resolve, reject, onCancel)
			local children = {}
			local decided = false

			local function conclude(settle)
				return function(...)
					cancelAll(children)
					decided = true
					return settle(...)
				end
			end

			if onCancel(conclude(reject)) then
				return
			end

			for index, promise in ipairs(promises) do
				children[index] = promise:andThen(conclude(resolve), conclude(reject))
			end

			if decided then
				cancelAll(children)
			end
		end)
	end

	function SunPromise.each(list, visitor)
		expectList(list, "SunPromise.each", 2)
		assert(callable(visitor), string.format(MSG.notAHandler, "SunPromise.each"))

		return SunPromise._new(debug.traceback(nil, 2), function(resolve, reject, onCancel)
			local output = {}
			local tracked = {}
			local aborted = false

			onCancel(function()
				aborted = true
				cancelAll(tracked)
			end)

			local queue = {}

			for index, item in ipairs(list) do
				if SunPromise.is(item) then
					local status = item:getStatus()

					if status == Status.Cancelled then
						cancelAll(tracked)
						return reject(Error.new({
							error = "SunPromise is cancelled",
							kind = Error.Kind.AlreadyCancelled,
							context = string.format(
								"The promise at index %d was already cancelled when SunPromise.each started.\n\nIt was created at:\n\n%s",
								index,
								tostring(item._origin)
							),
						}))
					elseif status == Status.Rejected then
						cancelAll(tracked)
						return reject(select(2, item:await()))
					end

					local mirror = item:andThen(function(...)
						return ...
					end)

					table.insert(tracked, mirror)
					queue[index] = mirror
				else
					queue[index] = item
				end
			end

			for index, item in ipairs(queue) do
				local current = item

				if SunPromise.is(current) then
					local ok
					ok, current = current:await()

					if not ok then
						cancelAll(tracked)
						return reject(current)
					end
				end

				if aborted then
					return
				end

				local step = SunPromise.resolve(visitor(current, index))
				table.insert(tracked, step)

				local ok, result = step:await()

				if not ok then
					cancelAll(tracked)
					return reject(result)
				end

				output[index] = result
			end

			resolve(output)
		end)
	end

	function SunPromise.is(object)
		if type(object) ~= "table" then
			return false
		end

		local meta = getmetatable(object)

		if meta == SunPromise then
			return true
		end

		if meta == nil then
			return callable(object.andThen)
		end

		if type(meta) == "table" then
			local index = rawget(meta, "__index")
			return type(index) == "table" and callable(rawget(index, "andThen"))
		end

		return false
	end

	function SunPromise.promisify(callback)
		return function(...)
			return SunPromise._try(debug.traceback(nil, 2), callback, ...)
		end
	end

	function SunPromise.delay(seconds)
		assert(type(seconds) == "number", "SunPromise.delay expects a number of seconds")
		local began = SunPromise._clock()

		return SunPromise._new(debug.traceback(nil, 2), function(resolve)
			task.delay(seconds, function()
				resolve(SunPromise._clock() - began)
			end)
		end)
	end

	function SunPromise.prototype:timeout(seconds, rejectionValue)
		local origin = debug.traceback(nil, 2)

		return SunPromise.race({
			SunPromise.delay(seconds):andThen(function()
				if rejectionValue ~= nil then
					return SunPromise.reject(rejectionValue)
				end

				return SunPromise.reject(Error.new({
					kind = Error.Kind.TimedOut,
					error = "Timed out",
					context = string.format(
						"Timed out after %s seconds.\n:timeout() was called at:\n\n%s",
						tostring(seconds),
						origin
					),
				}))
			end),
			self,
		})
	end

	function SunPromise.prototype:getStatus()
		return self._state
	end

	function SunPromise.prototype:_andThen(origin, onSuccess, onFailure)
		self._unobserved = false

		if self._state == Status.Cancelled then
			local dead = SunPromise.new(function() end)
			dead:cancel()

			return dead
		end

		return SunPromise._new(origin, function(resolve, reject, onCancel)
			local forwardOk = if onSuccess
				then relay(origin, onSuccess, resolve, reject)
				else resolve
			local forwardErr = if onFailure
				then relay(origin, onFailure, resolve, reject)
				else reject
			local state = self._state

			if state == Status.Started then
				table.insert(self._onResolve, forwardOk)
				table.insert(self._onReject, forwardErr)

				onCancel(function()
					if self._state == Status.Started then
						table.remove(self._onResolve, table.find(self._onResolve, forwardOk))
						table.remove(self._onReject, table.find(self._onReject, forwardErr))
					end
				end)
			elseif state == Status.Resolved then
				forwardOk(spill(self))
			elseif state == Status.Rejected then
				forwardErr(spill(self))
			end
		end, self)
	end

	function SunPromise.prototype:andThen(successHandler, failureHandler)
		assert(
			successHandler == nil or callable(successHandler),
			string.format(MSG.notAHandler, "SunPromise:andThen")
		)
		assert(
			failureHandler == nil or callable(failureHandler),
			string.format(MSG.notAHandler, "SunPromise:andThen")
		)

		return self:_andThen(debug.traceback(nil, 2), successHandler, failureHandler)
	end

	function SunPromise.prototype:catch(failureHandler)
		assert(
			failureHandler == nil or callable(failureHandler),
			string.format(MSG.notAHandler, "SunPromise:catch")
		)

		return self:_andThen(debug.traceback(nil, 2), nil, failureHandler)
	end

	function SunPromise.prototype:tap(tapHandler)
		assert(callable(tapHandler), string.format(MSG.notAHandler, "SunPromise:tap"))

		return self:_andThen(debug.traceback(nil, 2), function(...)
			local outcome = tapHandler(...)

			if SunPromise.is(outcome) then
				local kept = table.pack(...)

				return outcome:andThen(function()
					return table.unpack(kept, 1, kept.n)
				end)
			end

			return ...
		end)
	end

	function SunPromise.prototype:andThenCall(callback, ...)
		assert(callable(callback), string.format(MSG.notAHandler, "SunPromise:andThenCall"))
		local args = table.pack(...)

		return self:_andThen(debug.traceback(nil, 2), function()
			return callback(table.unpack(args, 1, args.n))
		end)
	end

	function SunPromise.prototype:andThenReturn(...)
		local values = table.pack(...)

		return self:_andThen(debug.traceback(nil, 2), function()
			return table.unpack(values, 1, values.n)
		end)
	end

	function SunPromise.prototype:cancel()
		if self._state ~= Status.Started then
			return
		end

		self._state = Status.Cancelled

		if self._cancelHook then
			self._cancelHook()
		end

		coroutine.close(self._runner)

		if self._upstream then
			self._upstream:_childCancelled(self)
		end

		for child in pairs(self._downstream) do
			child:cancel()
		end

		self:_finalize()
	end

	function SunPromise.prototype:_childCancelled(child)
		if self._state ~= Status.Started then
			return
		end

		self._downstream[child] = nil

		if next(self._downstream) == nil then
			self:cancel()
		end
	end

	function SunPromise.prototype:_finally(origin, handler)
		self._unobserved = false

		return SunPromise._new(origin, function(resolve, reject, onCancel)
			local pending

			onCancel(function()
				self:_childCancelled(self)

				if pending then
					pending:cancel()
				end
			end)

			local onDone = resolve

			if handler then
				onDone = function(...)
					local ok, out = guarded(origin, handler, ...)
					local first = out[1]

					if not ok then
						return reject(first)
					end

					if SunPromise.is(first) then
						pending = first

						first
							:finally(function(status)
								if status ~= Status.Rejected then
									resolve(self)
								end
							end)
							:catch(function(...)
								reject(...)
							end)
					else
						resolve(self)
					end
				end
			end

			if self._state == Status.Started then
				table.insert(self._onSettle, onDone)
			else
				onDone(self._state)
			end
		end)
	end

	function SunPromise.prototype:finally(finallyHandler)
		assert(
			finallyHandler == nil or callable(finallyHandler),
			string.format(MSG.notAHandler, "SunPromise:finally")
		)

		return self:_finally(debug.traceback(nil, 2), finallyHandler)
	end

	function SunPromise.prototype:finallyCall(callback, ...)
		assert(callable(callback), string.format(MSG.notAHandler, "SunPromise:finallyCall"))
		local args = table.pack(...)

		return self:_finally(debug.traceback(nil, 2), function()
			return callback(table.unpack(args, 1, args.n))
		end)
	end

	function SunPromise.prototype:finallyReturn(...)
		local values = table.pack(...)

		return self:_finally(debug.traceback(nil, 2), function()
			return table.unpack(values, 1, values.n)
		end)
	end

	function SunPromise.prototype:awaitStatus()
		self._unobserved = false

		if self._state == Status.Started then
			local thread = coroutine.running()

			self:finally(function()
				task.spawn(thread)
			end):catch(function() end)

			coroutine.yield()
		end

		if self._state == Status.Resolved or self._state == Status.Rejected then
			return self._state, spill(self)
		end

		return self._state
	end

	local function awaitResult(status, ...)
		return status == Status.Resolved, ...
	end

	function SunPromise.prototype:await()
		return awaitResult(self:awaitStatus())
	end

	local function expectResult(status, ...)
		if status ~= Status.Resolved then
			error((...) == nil and "Expected SunPromise rejected with no value." or (...), 3)
		end

		return ...
	end

	function SunPromise.prototype:expect()
		return expectResult(self:awaitStatus())
	end

	SunPromise.prototype.awaitValue = SunPromise.prototype.expect

	function SunPromise.prototype:_unwrap()
		if self._state == Status.Started then
			error("SunPromise has not resolved or rejected.", 2)
		end

		return self._state == Status.Resolved, spill(self)
	end

	function SunPromise.prototype:_resolve(...)
		local head = ...

		if self._state ~= Status.Started then
			if SunPromise.is(head) and type(head._childCancelled) == "function" then
				head:_childCancelled(self)
			end

			return
		end

		if SunPromise.is(head) then
			if select("#", ...) > 1 then
				warn(
					string.format(
						"Extra arguments are dropped when a SunPromise is returned from andThen. Created at:\n\n%s",
						self._origin
					)
				)
			end

			local adopted = head:andThen(function(...)
				self:_resolve(...)
			end, function(...)
				local payload = head._result or head._values
				local culprit = payload and payload[1]

				if head._error then
					culprit = Error.new({
						error = head._error,
						kind = Error.Kind.ExecutionError,
						context = "[No stack trace available as this SunPromise came from an older version of the SunPromise library (< v2)]",
					})
				end

				if Error.isKind(culprit, Error.Kind.ExecutionError) then
					return self:_reject(culprit:extend({
						error = "This SunPromise was chained to a SunPromise that errored.",
						trace = "",
						context = string.format(
							"The SunPromise at:\n\n%s\n...was rejected because it was chained to a SunPromise that errored:\n",
							self._origin
						),
					}))
				end

				self:_reject(...)
			end)

			if adopted._state == Status.Cancelled then
				self:cancel()
			elseif adopted._state == Status.Started then
				self._upstream = adopted
				adopted._downstream[self] = true
			end

			return
		end

		self._state = Status.Resolved
		self._result = table.pack(...)

		flush(self._onResolve, ...)
		self:_finalize()
	end

	function SunPromise.prototype:_reject(...)
		if self._state ~= Status.Started then
			return
		end

		self._state = Status.Rejected
		self._result = table.pack(...)

		if next(self._onReject) ~= nil then
			flush(self._onReject, ...)
		else
			local text = tostring((...))

			coroutine.wrap(function()
				SunPromise._pulse:Wait()

				if not self._unobserved then
					return
				end

				local report = string.format(
					"Unhandled rejection in SunPromise:\n\n%s\n\nPromise created at:\n%s",
					text,
					self._origin
				)

				for _, listener in ipairs(SunPromise._rejectionListeners) do
					task.spawn(listener, self, spill(self))
				end

				if SunPromise.TEST then
					return
				end

				warn(report)
			end)()
		end

		self:_finalize()
	end

	function SunPromise.prototype:_finalize()
		flush(self._onSettle, self._state)

		self._onSettle = nil
		self._onReject = nil
		self._onResolve = nil

		if not SunPromise.TEST then
			self._upstream = nil
			self._downstream = nil
		end

		task.defer(coroutine.close, self._runner)
	end

	function SunPromise.prototype:now(rejectionValue)
		local origin = debug.traceback(nil, 2)

		if self._state == Status.Resolved then
			return self:_andThen(origin, function(...)
				return ...
			end)
		end

		if rejectionValue ~= nil then
			return SunPromise.reject(rejectionValue)
		end

		return SunPromise.reject(Error.new({
			kind = Error.Kind.NotResolvedInTime,
			error = "This SunPromise was not resolved in time for :now()",
			context = ":now() was called at:\n\n" .. origin,
		}))
	end

	function SunPromise.retry(callback, times, ...)
		assert(callable(callback), "SunPromise.retry expects a function as argument #1")
		assert(type(times) == "number", "SunPromise.retry expects a number as argument #2")

		local args = table.pack(...)

		return SunPromise.resolve(callback(...)):catch(function(...)
			if times > 0 then
				return SunPromise.retry(callback, times - 1, table.unpack(args, 1, args.n))
			end

			return SunPromise.reject(...)
		end)
	end

	function SunPromise.retryWithDelay(callback, times, seconds, ...)
		assert(
			callable(callback),
			"SunPromise.retryWithDelay expects a function as argument #1"
		)
		assert(
			type(times) == "number",
			"SunPromise.retryWithDelay expects a number as argument #2"
		)
		assert(
			type(seconds) == "number",
			"SunPromise.retryWithDelay expects a number as argument #3"
		)

		local args = table.pack(...)

		return SunPromise.resolve(callback(...)):catch(function(...)
			if times > 0 then
				SunPromise.delay(seconds):await()

				return SunPromise.retryWithDelay(
					callback,
					times - 1,
					seconds,
					table.unpack(args, 1, args.n)
				)
			end

			return SunPromise.reject(...)
		end)
	end

	function SunPromise.fromEvent(event, filter)
		local accept = filter or function()
			return true
		end

		return SunPromise._new(debug.traceback(nil, 2), function(resolve, _, onCancel)
			local link
			local dropEarly = false

			local function drop()
				link:Disconnect()
				link = nil
			end

			link = event:Connect(function(...)
				local verdict = accept(...)

				if verdict == true then
					resolve(...)

					if link then
						drop()
					else
						dropEarly = true
					end
				elseif type(verdict) ~= "boolean" then
					error("SunPromise.fromEvent filter must always return a boolean")
				end
			end)

			if dropEarly and link then
				return drop()
			end

			onCancel(drop)
		end)
	end

	function SunPromise.onUnhandledRejection(callback)
		table.insert(SunPromise._rejectionListeners, callback)

		return function()
			local position = table.find(SunPromise._rejectionListeners, callback)

			if position then
				table.remove(SunPromise._rejectionListeners, position)
			end
		end
	end

	return SunPromise
end
