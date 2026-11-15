# poethepoet: 15 changes between v0.33.0 and v0.45.0

The workspace is poethepoet (Poe the Poet, a task runner for Python projects, MIT licence) at v0.33.0. Below are
15 separate changes from its later history, each described the way its maintainers described it. None is done
yet. Make all of them in the repository in `/workspace`. Most are independent; some build on an earlier one (U02 builds on U01; U03 builds on U02),
so make those after the change they build on.

Tests run offline from the workspace: `python -m pytest tests -m "not slow"` (the slow tests build virtual
environments; tests that need the `uv` program are skipped when it is missing). The existing tests may need updating
where a change alters documented output. Behaviour that none of the changes mentions must stay as it is.

### U01: Don't resolve symlinks to uv in UvExecutor

The uv executor runs the wrong program when uv is installed through Snap on Ubuntu. Snap exposes every installed command as a symlink to one wrapper binary, and the wrapper decides which package to run from the name it was called as. The uv executor finds uv on the PATH correctly (the symlink in the snap bin directory) but then resolves the symlink itself, so it ends up calling the wrapper under its own name. Every task then fails, for example with `snap "black" is not installed`. The executor must call the uv executable under the path it found it by, and leave symlink resolution to the operating system and shell.

### U02: Make UvExecutor set directory and project options on uv run

Make the uv executor set the directory and project options on `uv run`. In a monorepo whose root is not a uv project, a task with a `cwd` option pointing at the root, declared in a sub-project that is a uv project and run as `uv run poe the-task` from there, fails: poe runs the task with `uv run` inside the task's working directory, so uv looks for a project in that directory and not in the one poe was configured for. The environment must stay the one of the poe project. When the task has a working directory, the uv executor must pass uv the options that name both that directory (`--directory`) and the poe project's directory (`--project`) explicitly. (The issue's reporter suggested reusing `VIRTUAL_ENV` instead; the maintainers chose to pass the two options.) 

### U03: Add task packages feature

Add task packages: load task definitions from python code. The PR text calls the option `task_packages`, but the option the maintainers implemented and documented is `include_script`; use that name. It is a global option in `[tool.poe]`, taking one item or a list. An item is a function reference in the same syntax as a script task (`package:function`, optionally with literal arguments such as `package:function(prefix='x-')`), or a table with `script`, and optionally `executor` and `cwd`. poe imports and calls the function and uses the value it returns as additional config, the same structure the `include` option accepts from another file (a dict, or a JSON string, with `tasks`, `env` and `envfile`). The function must not write to stdout. The package must be importable by the project's default executor, so the call runs in a subprocess of that executor; an item's own `executor` overrides it, and an item's `cwd` sets the working directory (and the config directory) for the tasks it includes, exactly as `cwd` does for `include` items. Tasks from a packaged script show up in the help listing like any other. Also, as the same change: executor auto-detection now takes a `poetry.lock` or a `uv.lock` in the project into account, and `cmd` tasks must resolve `$POE_ACTIVE` in their content. Document the feature in a new guide page.

### U04: Don't register hidden tasks with poetry plugin

Don't register hidden tasks with the poetry plugin. Tasks whose names start with an underscore are hidden tasks (documented as not meant to be run directly); the poetry plugin currently registers them as poetry commands, so they show up in `poetry help` alongside the real ones. They must not be registered, whether or not a command prefix is configured.

### U05: Simplify CLI help page header

Simplify the CLI help page header. The help page currently opens with a two-part banner (a tagline about being a task runner that works well with poetry, then the version). Make it a single short header line naming the program and its version, in the form `Poe the Poet (version X.Y.Z)` where X.Y.Z is the installed version, so that the help output starts with that line.

### U06: Don't resolve symlinks to poetry in PoetryExecutor

Don't resolve symlinks to poetry in the poetry executor. This is the same problem the uv executor had when uv is installed through Snap: the executor resolves the symlink it found on the PATH and so executes the Snap wrapper under its own name instead of poetry. The executor must call poetry under the path it found it by.

### U07: Crash with invalid help option on task

Fix a crash with an invalid `help` option on a task. When a task's `help` option is not a string (the config is invalid in that respect), building the task listing for the help page raises an unhandled exception. It must not crash.

### U09: Coerce switch case values to string to avoid errors

Coerce switch case values to strings to avoid errors. In a switch task a case may be written with a non-string TOML value, such as the integer `0` or `1`, or a list of them. Such a case value is interpreted as its string form, so that it matches the string the control task produces, and the switch task runs without error.

### U10: Always print help when no arguments provided

Always print the help page when poe is run with no arguments, even if the project's default verbosity is negative (set in the project configuration). Explicitly lowering the verbosity on the command line still applies.

### U12: Suppress irrelevant global options in the poetry plugin cli

Suppress irrelevant global options in the poetry plugin CLI. When poe runs as a poetry plugin, the help page of its command lists poe's own global options, several of which do not work or make no sense there because poetry owns them: help, version, verbosity, the project root options and the ANSI options. They must not be listed in the plugin's help. Running poe standalone keeps listing them (the legacy `--root` option stays hidden from the standalone help, as it is today).

### U14: Fix typos

Fix typos. In the documentation guide on global tasks, "uze" should read "use". In the expression task implementation, a method declares its `imports` parameter with an `=` where a `:` type annotation was meant. This is a no-behaviour change.

### U15: Fix issue in locating sh.exe when git is installed in a custom location

Locating `sh.exe` on Windows fails when git is installed in a non-default location. The shell task looks for git's `sh.exe` only under the default Program Files location. When that fails and `git` is found on the PATH, look for `sh.exe` relative to the git executable as well, so that installs without admin rights (for example under the user's AppData directory) work.

### U27: Global executor option

The global `executor` option accepts a plain string, as the task-level one does. Today, `executor = "simple"` on a task works, but the same string at the global level (`[tool.poe]`) results in an error. Make the global form work and mean the same as `executor = { type = "simple" }`.

### U29: Ensure the test virtual environment is always removed

Make sure the test suite's temporary virtual environments are always removed. If the test run is interrupted (Ctrl-C), a test virtual environment can be left behind and then makes the next test run fail. The cleanup in the test fixtures must always run, also on interruption.

### U43: Preserve quotes in :+/:- operator arguments

Preserve quotes in the arguments of the `:+` and `:-` parameter-expansion operators in cmd tasks. With `cmd = "echo pytest ${SKIP_BUILD:+ -m 'not build'}"` and `SKIP_BUILD` set, poe produces three arguments (`-m`, `not`, `build`) instead of two (`-m`, `not build`): the quotes inside the alternate value are dropped, which changes the word splitting. The same holds for the default-value operator `:-`. Quoted text in these arguments must stay a single argument when the expansion is unquoted; inside an already-quoted context the value is still used as one string, as in bash. Glob patterns inside the arguments are treated as literal text (a known divergence from bash, which the cmd task documentation should note).

Do not run `scripts/release.sh`; the user releases after review.

When you finish, report for each change (U01, U02, ...) whether it is done.
