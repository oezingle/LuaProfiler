
local debug_getinfo = (debug or {}).getinfo
local debug_sethook = (debug or {}).sethook

if not (debug_getinfo and debug_sethook) then
    error("profiler requires debug.getinfo and debug.sethook")
end


--[[
    Adapted from https://jan.kneschke.de/projects/misc/profiling-lua-with-kcachegrind/

    Profiler
        - init(opts) create, with options
            - sentient: boolean - lets the profiler track itself.
        - start() start monitoring
        - stop() stop monitoring
        - dump(file, format) dump to a file of a given format

    Implemented formats
        - KCacheGrind
]]

---@class Zingle.Profiler.Function.Call
---@field fn function
---@field instruction_count number

---@class Zingle.Profiler.Function.Line
---@field current_line number
---@field instruction_count number

---@alias Zingle.Profiler.Function.Event { type: "line", line: Zingle.Profiler.Function.Line } | { type: "call", call: Zingle.Profiler.Function.Call }


---@class Zingle.Profiler.Function
---@field short_src string
---@field name string
---@field linedefined number
---@field lastlinedefined number
---@field events Zingle.Profiler.Function.Event[]


---@alias Zingle.Profiler.CallstackItem (debuginfo | { instruction_count: number })



---@class Zingle.Profiler
---
---@field protected instruction_count number
---@field protected last_instruction_count number
---
---@field protected main_fn Zingle.Profiler.CallstackItem
---
---@field protected methods table<function, string>
---@field protected discovered table<table, true>
---
---@field protected callstack Zingle.Profiler.CallstackItem[]
---@field protected functions table<function, Zingle.Profiler.Function>
---@field protected ignore table<function, true>
---
---@field protected ignore_paths string[]
---
---@field start fun(opts?: { sentient: boolean?, ignore?: string[] })
---@field ignore_path fun(...: string)
---@field reset fun(opts?: { sentient: boolean?, ignore?: string[] })
---@field stop fun()
---@field dump fun(filename: string, format: "callgrind")
local profiler = {}

function profiler.reset(opts)
    opts = opts or {}

    profiler.instruction_count = 0
    profiler.last_instruction_count = 0

    profiler.methods = {}
    profiler.discovered = {}

    profiler.callstack = {}
    profiler.functions = {}

    profiler.ignore = {}

    if not opts.sentient then
        for _, v in pairs(profiler) do
            if type(v) == "function" then
                profiler.ignore[v] = true
            end
        end
    end

    profiler.ignore_paths = {}

    if opts.ignore then
        profiler.ignore_path(table.unpack(opts.ignore))
    end
end

---@param ... string paths to ignore
function profiler.ignore_path(...)
    for _, path in ipairs(table.pack(...)) do
        table.insert(profiler.ignore_paths, path)
    end
end

function profiler.discover_all_methods()
    -- TODO first do some sort of require() traversal?

    profiler.discovered[package.loaded] = true

    profiler.discover_methods(_G)
end

---@param input any
---@param name string?
function profiler.discover_methods(input, name)
    if type(input) == "table" then
        profiler.discovered[input] = true

        local prefix = name and (name .. ".") or ""

        for key, value in pairs(input) do
            if type(key) == "string" and not profiler.discovered[value] then
                -- TODO handle imported packages. like duh we know their location

                -- if prefix:match("^package.loaded%.") and key:match("%.") then
                --     self:discover_methods(value, name)
                -- else
                profiler.discover_methods(value, prefix .. key)
                -- end
            end
        end
    elseif type(input) == "function" then
        if name then
            profiler.methods[input] = name
        end
    end
end

-- TODO could use a table to get function names w/ classes & tables, etc. in the future
---@param f_info debuginfo
function profiler.get_function_name(f_info)
    return
        profiler.methods[f_info.func] or
        f_info.name or
        f_info.what or
        f_info.short_src .. ":" .. tostring(f_info.linedefined)
end

---@param f_info debuginfo
function profiler.get_short_src(f_info)
    if profiler.methods[f_info.func] and not profiler.methods[f_info.func]:match("^package%.loaded%.") then
        return "Lua library function"
    end

    return
        f_info.short_src
end

---@param f_info debuginfo
---@param add { line: Zingle.Profiler.Function.Line?, call: Zingle.Profiler.Function.Call? }
function profiler.function_add(f_info, add)
    local addr = f_info.func

    if not profiler.functions[addr] then
        ---@type Zingle.Profiler.Function
        local entry = {
            short_src = profiler.get_short_src(f_info),
            name = profiler.get_function_name(f_info),
            linedefined = f_info.linedefined or -1,
            lastlinedefined = f_info.lastlinedefined or -1,
            events = {}
        }

        profiler.functions[addr] = entry
    end

    local entry = profiler.functions[addr]

    if not profiler.main_fn then
        profiler.main_fn = f_info
    end

    if add.line then
        ---@type Zingle.Profiler.Function.Event
        local line_entry = { type = "line", line = add.line }

        table.insert(entry.events, line_entry)
    end

    if add.call then
        ---@type Zingle.Profiler.Function.Event
        local line_entry = { type = "call", call = add.call }

        table.insert(entry.events, line_entry)
    end
end

---@param f_info debuginfo
function profiler.function_get(f_info)
    return profiler.functions[f_info.func]
end

---@param f_info Zingle.Profiler.CallstackItem
function profiler.callstack_add(f_info)
    f_info.instruction_count = profiler.instruction_count

    table.insert(profiler.callstack, f_info)
end

function profiler.callstack_current()
    return profiler.callstack[#profiler.callstack]
end

---@return Zingle.Profiler.CallstackItem
function profiler.callstack_remove()
    return table.remove(profiler.callstack, #profiler.callstack)
end

---@param class "count" | "line" | "call" | "return"
function profiler.trace(class)
    -- print(class)

    local f_info = debug_getinfo(2, "lSfn")

    if profiler.ignore[f_info.func] then
        return
    end

    for _, ignore_path in ipairs(profiler.ignore_paths) do
        if f_info.short_src:match(ignore_path) then
            return
        end
    end

    if class == "count" then
        profiler.instruction_count = profiler.instruction_count + 1
    elseif class == "line" then
        profiler.function_add(f_info, {
            line = {
                current_line = f_info.currentline,
                instruction_count = profiler.instruction_count - profiler.last_instruction_count
            }
        })

        profiler.last_instruction_count = profiler.instruction_count
    elseif class == "call" then
        -- local f_name = get_function_name(f_info)

        profiler.callstack_add(f_info)

        profiler.function_add(f_info, {})
    elseif class == "return" and #profiler.callstack > 0 then
        local popped_info = profiler.callstack_remove()

        -- TODO weird pcall handler?

        local prev = #profiler.callstack > 0 and profiler.callstack_current() or profiler.main_fn

        profiler.function_add(prev, {
            call = {
                fn = popped_info.func,
                instruction_count = profiler.instruction_count - popped_info.instruction_count
            }
        })
    end
end

function profiler.start(opts)
    profiler.reset(opts)

    profiler.discover_all_methods()

    debug_sethook(profiler.trace, "crl", 1)
end

function profiler.stop()
    debug_sethook()
end

local LOOP_PANIC_MAX = 1024

--- If filename exists, convert the string to filename-1, filename-2, ...
---@param path string
---@return string path
function profiler.find_unused_filename(path)
    local i = 0

    while io.open(path, "r") do
        path = path:gsub("%-(%d+)$", function(index_str)
            local index = tonumber(index_str)

            return "-" .. tostring(index + 1)
        end)

        -- see if the file has been suffixed with -(number)
        if not path:match("%-(%d+)$") then
            path = path .. "-1"
        end

        if i >= LOOP_PANIC_MAX then
            error(string.format("Unable to find unused filename after %d iterations. Please rename callgrind files", LOOP_PANIC_MAX))
        end

        i = i + 1
    end

    return path
end

---@param file file*
---@param fmt string
---@param ... any
local function write_format(file, fmt, ...)
    local str = string.format(fmt, ...)

    return file:write(str)
end

--- TODO does not total to 100%?
---@param file file*
function profiler.to_callgrind(file)
    file:write("events: Instructions\n")

    for _, entry in pairs(profiler.functions) do
        write_format(file, "fl=%s\n", entry.short_src)
        write_format(file, "fn=%s\n", entry.name)

        for _, event in ipairs(entry.events) do
            local event_type = event.type

            if event_type == "line" then
                local line = event.line

                write_format(file, "%d %d\n", line.current_line, line.instruction_count)
            elseif event_type == "call" then
                local call = event.call

                local call_info = profiler.functions[call.fn]

                write_format(file, "cfl=%s\n", call_info.short_src)
                write_format(file, "cfn=%s\n", call_info.name)

                write_format(file, "calls=1 %d\n", call_info.linedefined)

                write_format(file, "%d %d\n", call_info.lastlinedefined, call.instruction_count)
            end
        end

        write_format(file, "\n")

        file:flush()
    end
end

---@param filename string
---@param format "callgrind"
function profiler.dump(filename, format)
    -- save us from a crazy memory leak
    profiler.stop()

    local filename = profiler.find_unused_filename(filename)

    local handlers = {
        callgrind = profiler.to_callgrind
    }

    if not format then
        local handler_strs = {}
        for fmt in pairs(handlers) do
            table.insert(handler_strs, string.format("%q", fmt))
        end

        error(string.format("Format must be one of: %s", table.concat(handler_strs, ", ")))
    end

    local format_handler = handlers[format]

    if not format_handler then
        error(string.format(
            "Unknown profiler format \"%s\"",
            format
        ))
    end

    local file = io.open(filename, "w")

    if not file then
        error(string.format(
            "Unable to open %s",
            filename
        ))
    end

    format_handler(file)

    profiler.reset()
end

return profiler
