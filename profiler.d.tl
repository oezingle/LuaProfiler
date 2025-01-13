
local interface ProfilerOptions
    sentient: boolean | nil
    ignore: {string} | nil
end

local enum ProfilerFormat
    "callgrind"
end

local record profiler 
    start: function (options?: ProfilerOptions)

    ignore_path: function (...: string)

    reset: function (options?: ProfilerOptions)
    
    stop: function ()

    dump: function (filename: string, format: ProfilerFormat)
end

return profiler