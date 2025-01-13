
# LuaProfiler

A small Lua module inspired by [Jan Kneschke's blog article](https://jan.kneschke.de/projects/misc/profiling-lua-with-kcachegrind/), which provides code that seems to be defunct in modern versions of Lua. Tested under `Lua 5.4.7` and `LuaJit 2.1`. 

## API

`profiler.start(opts?)` Start profiling. opts = { sentient: boolean, ignore: string[] }. opts.sentient reflects whether or not the profiler will include its own functions in the output, and ignore is a list of paths that the profiler should not observe

`profiler.ignore_path(...paths)` Ignore one or multiple paths. Note that paths must be exact - no wildcard or platform-agnostic matching is done by the profiler.

`profiler.stop()` Stop profiling.

`profiler.dump(filename, format)` Stop profiling and output the captured results to a file. if this path already exists, the profiler will automatically append a numeric suffix to the file. For supported formats, see [Formats](#formats)

### Formats

Currently, only `"callgrind"` is supported. This format is the same as that outputted by valgrind's callgrind sibling tool, and is read easily by the KDE team's excellent [KCacheGrind](https://kcachegrind.github.io/html/Home.html) viewing tool.

## Limitations

The profiler is not written with speed in mind. Correctness and extensibility have been put first. Additionally, execution "time" is estimated by lua's line hook. However, this generally provides accurate 