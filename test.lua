
local profiler = require("profiler")

local p = profiler

p.start()

local function hello_world ()
    print("Hello World!")
end

hello_world()

p.stop()

p.dump("test.callgrind", "callgrind")