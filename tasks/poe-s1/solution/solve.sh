#!/bin/bash
set -euo pipefail
cd "${WORKSPACE:-/workspace}"
git apply --whitespace=nowarn <<'COLLAB_REFERENCE_PATCH_EOF'
diff --git a/README.md b/README.md
index 99505cb..3c0994c 100644
--- a/README.md
+++ b/README.md
@@ -17,7 +17,7 @@
 
 - ✅ Straight forward [declaration of project tasks in your pyproject.toml](https://poethepoet.natn.io/tasks/index.html) (or [poe_tasks.toml](https://poethepoet.natn.io/guides/without_poetry.html#usage-without-pyproject-toml))
 
-- ✅ Tasks are run in poetry's virtualenv ([or another env](https://poethepoet.natn.io/index.html#usage-without-poetry) you specify)
+- ✅ Tasks are run in poetry or uv's virtualenv ([or another env](https://poethepoet.natn.io/index.html#usage-without-poetry) you specify)
 
 - ✅ [Shell completion of task names](https://poethepoet.natn.io/installation.html#shell-completion) (and global options too for zsh)
 
@@ -27,7 +27,7 @@
 
 - ✅ Concise commands with extra arguments passed to the task `poe [options] task [task_args]`
 
-- ✅ Easily [define CLI arguments](https://poethepoet.natn.io/guides/args_guide.html) for your tasks
+- ✅ Easily [declare named CLI arguments](https://poethepoet.natn.io/guides/args_guide.html) for your tasks
 
 - ✅ Tasks can specify and [reference environment variables](https://poethepoet.natn.io/tasks/task_types/cmd.html#ref-env-vars), even without a shell
 
@@ -39,7 +39,10 @@
 
 - ✅ Can be [used as a library](https://poethepoet.natn.io/guides/library_guide.html) to embed in other tools
 
-- ✅ Also works fine [without poetry](https://poethepoet.natn.io/guides/without_poetry.html)
+- ✅ Tasks can be [defined in python packages](https://poethepoet.natn.io/guides/packaged_tasks.html) for ease of reuse across projects
+
+- ✅ Also works fine as a [general purpose task runner](https://poethepoet.natn.io/guides/without_poetry.html)
+
 
 ## Quick start
 
diff --git a/docs/global_options.rst b/docs/global_options.rst
index 3a758b9..5bf0b23 100644
--- a/docs/global_options.rst
+++ b/docs/global_options.rst
@@ -13,9 +13,12 @@ The following options can be set for all tasks in a project directly under ``[to
 **executor** : ``dict[str, str]`` :ref:`📖<Change the executor type>`
   Override the default behavior for selecting an executor for tasks in this project.
 
-**include** : ``str`` | ``list[str]`` | ``dict[str, str]`` :doc:`📖<../guides/include_guide>`
+**include** : ``str`` | ``dict[str, str]`` | ``list[str | dict[str, str]]`` | :doc:`📖<../guides/include_guide>`
   Specify one or more other toml or json files to load tasks from.
 
+**include_script** : ``str`` | ``dict[str, str]`` | ``list[str | dict[str, str]]`` :doc:`📖<../guides/packaged_tasks>`
+  Load dynamically generated tasks from one or more python functions. This is similar to the :doc:`include global option<../guides/include_guide>`, except instead of providing paths to config files, one can reference python functions that generate task config, using the same syntax as for :doc:`script tasks<../tasks/task_types/script>`.
+
 **shell_interpreter** : ``str`` | ``list[str]`` :ref:`📖<Change the default shell interpreter>`
   Change the default interpreter to use for executing :doc:`shell tasks<../tasks/task_types/shell>`.
 
diff --git a/docs/guides/global_tasks.rst b/docs/guides/global_tasks.rst
index d7ceba4..a8d6a13 100644
--- a/docs/guides/global_tasks.rst
+++ b/docs/guides/global_tasks.rst
@@ -24,7 +24,7 @@ You can choose any location to define the tasks, and whatever name you like for
 Shell completions for global tasks
 ----------------------------------
 
-If you uze zsh or fish then the usual completion script should just work with your alias (as long as it was created with poethepoet >=0.28.0).
+If you use zsh or fish then the usual completion script should just work with your alias (as long as it was created with poethepoet >=0.28.0).
 
 However for bash you'll need to generate a new completion script for the alias specifying the alias and the path to you global tasks like so:
 
diff --git a/docs/guides/include_guide.rst b/docs/guides/include_guide.rst
index a7ecf34..791e17d 100644
--- a/docs/guides/include_guide.rst
+++ b/docs/guides/include_guide.rst
@@ -10,15 +10,13 @@ There are some scenarios where one might wish to define tasks outside of pyproje
 For example:
 
 .. code-block:: toml
-
-  # pyproject.toml
+  :caption: ./pyproject.toml
 
   [tool.poe]
   include = "modules/acme_common/shared_tasks.toml" # include tasks from a git submodule
 
 .. code-block:: toml
-
-  # acme_common/shared_tasks.toml
+  :caption: ./modules/acme_common/shared_tasks.toml
 
   [tool.poe.tasks.build-image]
   cmd = "docker build"
@@ -26,11 +24,19 @@ For example:
 Imported files may also specify environment variables via
 ``tool.poe.envfile`` or entries for ``tool.poe.env``.
 
-.. tip::
+.. warning::
 
   If a referenced file is missing then poe ignores it without error, though failure to read the contents will result in failure.
 
 
+Including tasks from a python package
+-------------------------------------
+
+You can also include tasks from a python function originating either within the current project or from a dependency. This makes it much easier to share tasks across projects by distributing them as a python package, or to dynamically generate tasks depending on the context.
+
+For more details see the :doc:`include_scripts<../guides/packaged_tasks>` global option.
+
+
 Including multiple files
 ------------------------
 
diff --git a/docs/guides/index.rst b/docs/guides/index.rst
index 5511fba..80e3243 100644
--- a/docs/guides/index.rst
+++ b/docs/guides/index.rst
@@ -11,6 +11,7 @@ This section contains guides for using the various features of Poe the Poet.
    args_guide
    composition_guide
    include_guide
+   packaged_tasks
    global_tasks
    without_poetry
    library_guide
diff --git a/docs/guides/packaged_tasks.rst b/docs/guides/packaged_tasks.rst
new file mode 100644
index 0000000..63fec42
--- /dev/null
+++ b/docs/guides/packaged_tasks.rst
@@ -0,0 +1,217 @@
+Loading tasks from a python package
+===================================
+
+Usually tasks are declared in a config file such as pyproject.toml, however you can also define tasks in python, and *include* them into your project config via the ``include_script`` global option.
+
+This is primarily intended to make it easier to reuse tasks across projects – by distributing them as a python package. However you can also use it to define tasks with a local script file.
+
+
+The ``include_script`` global option
+------------------------------------
+
+The following config loads the tasks generated by running the ``get_tasks`` function from the ``mypkg`` package. The package must be accessible to the default :ref:`executor<Change the executor type>`, i.e. it must be within the current project or its dependencies.
+
+.. code-block:: toml
+
+  [tool.poe]
+  include_script = "mypkg:get_tasks"
+
+Just like for the :ref:`include<Loading tasks from another file>` global option, you can also provide a multiple items like so:
+
+.. code-block:: toml
+
+  [tool.poe]
+  include_script = ["mypkg:get_tasks", "something.else:more_tasks"]
+
+
+Passing arguments to the script
+~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
+
+The syntax for the function reference is identical to a :doc:`script task<../tasks/task_types/script>`, meaning that it is also possible to pass arguments to the function like so:
+
+.. code-block:: toml
+
+  [tool.poe]
+  include_script = "mypkg:get_tasks(task_prefix='foo-', exclude_tasks='docs')"
+
+
+Specifying a different executor
+~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
+
+Normally Poe the Poet detects the most appropriate :ref:`executor<Change the executor type>` (i.e. project virtualenv) to use to find and execute the referenced package. However you can customize this behavior by specify an executor for the script like so:
+
+.. code-block:: toml
+
+  [[tool.poe.include_script]]
+  script   = "mypkg:get_tasks"
+  executor = { type = "virtualenv", location = "../parent.venv" }
+
+
+Setting a working directory for included config
+~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
+
+You can use the ``cwd`` option on an include_script to make the included tasks run with a different working directory. This option behaves exactly like the :ref:`similar option for include items<Setting a working directory for included tasks>`.
+
+.. code-block:: toml
+
+  [tool.poe]
+  include_script = [
+    { script = "mypkg:get_tasks", cwd = "./subproject1" }
+  ]
+
+
+Out-of-the-box tasks from *poethepoet-tasks*
+--------------------------------------------
+
+With ``include_scripts`` you can reuse common tasks in each new project by depending directly on a private or public *tasks package*. As an example the |poethepoet_tasks_link| package provides an opinionated collection of tasks to get you started, with two simple steps:
+
+1. Add a dev dependency on ``poethepoet-tasks``
+
+   .. code-block:: sh
+     :caption: with poetry
+
+     poetry add poethepoet-tasks -G dev
+
+   .. code-block:: sh
+     :caption: with uv
+
+     uv add --dev poethepoet-tasks
+
+2. Configure your project to include tasks from ``poethepoet-tasks``
+
+   .. code-block:: toml
+     :caption: pyproject.toml
+
+     [tool.poe]
+     include_script = "poethepoet_tasks:tasks"
+
+See the docs for |poethepoet_tasks_link| for details of how you can include just a specific subset of available tasks.
+
+
+Create your own tasks package
+-----------------------------
+
+To create your own tasks package, all you need is a python function that returns the required config structure (as a dict or json string), that can be imported from within your project, either from within the project itself or from a dependency.
+
+
+Generating config directly
+~~~~~~~~~~~~~~~~~~~~~~~~~~
+
+The following example illustrates defining a function that can be referenced by ``include_script``:
+
+.. code-block:: python
+
+  def generate_tasks():
+    return {
+      "tasks": {
+        "test": "pytest",
+        "build-proto": {
+          "cmd": """
+            protoc --proto_path=schemas --python_out=src/generated schemas/messages.proto
+          """,
+          "help": "Generate protobuf classes"
+        },
+        "build": {
+          "sequence": [
+            "build-proto",
+            "test",
+            { "cmd": "poetry build" },
+          ],
+          "help": "Build that code"
+        }
+      }
+    }
+
+You may recognise the structure as identical to that supported when :doc:`loading tasks from another file<../guides/include_guide>`, which is a subset of the schema supported in the main project configuration, including ``tasks`` and the ``env`` and ``envfile`` :doc:`global options<../global_options>`.
+
+There is no restriction on the arguments accepted by the function, or the logic used to generate the tasks. However it is critical that the function does not write anything to stdout.
+
+.. warning::
+  It is **strongly recommended** to minimize the code that must be imported or executed to generate the tasks configuration. This is because the poe CLI must create a python subprocess to import and execute the function every time it is used within the project; even when generating shell completions. This is also a good reason to ensure there are no side effects of this code or any of its imports.
+
+
+Defining a TaskCollection
+~~~~~~~~~~~~~~~~~~~~~~~~~
+
+The recommended way to write tasks in python is to leverage the **TaskCollection** abstraction from |poethepoet_tasks_link|. It provides a convenient API for managing tasks, and allows users to select just the tasks they want via tags.
+
+.. code-block:: python
+  :caption: src/my_tasks/__init__.py
+
+  from poethepoet_tasks import TaskCollection
+
+  tasks = TaskCollection()
+
+  # Define a simple cmd task
+  tasks.add(
+      task_name="test",
+      task_config={
+          "help": "Run project tests",
+          "cmd": "pytest tests",
+      },
+      tags=["pytest"], # tags are optional and allow consumers to select only the desired tasks
+  )
+
+The TaskCollection instance is callable such that it can be referenced directly like so:
+
+.. code-block:: python
+  :caption: pyproject.toml
+
+  [tool.poe]
+  include_script = "my_tasks:tasks"
+
+
+Decorating functions as script tasks
+~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
+
+A TaskCollection can also be used to define inline :doc:`script tasks<../tasks/task_types/script>`. One nice pattern this enables is to have a `tasks.py` in the root of your project, similar to how one would work with *invoke*.
+
+
+.. code-block:: python
+  :caption: tasks.py
+
+  from poethepoet_tasks import TaskCollection
+
+  tasks = TaskCollection()
+
+  # Define an inline script task
+  @tasks.script(tags=["example"])
+  def hello(
+      foo: str | None = None,
+      *, # This means preceding args will be positional, instead of CLI options
+      bar: int = 1,
+      baz: bool = True,
+  ):
+      """
+      The first paragraph of the function docstring is picked up as the task help message!
+
+      Args:
+          foo: a positional argument for specifying foo
+          bar: a number of things
+          baz: to baz or not to baz
+      """
+      pass
+
+The above example is equivalent to the following toml based configuration:
+
+.. code-block:: toml
+  :caption: pyproject.toml
+
+  [tool.poe.tasks.hello]
+  script = "tasks:hello(foo, bar=bar, baz=baz)"
+  help   = "The first paragraph of the function docstring is picked up as the task help message!"
+  args   = [
+    { name = "foo", positional = true, help = "a positional argument for specifying foo" },
+    { name = "bar", help = "a number of things" },
+    { name = "baz", help = "to baz or not to baz" }
+  ]
+
+
+.. tip::
+
+  When creating an inline script task via the TaskCollection decorator most of task options are automatically infered from the code, including task name, args, and help text (given a sufficient docstring).
+
+
+.. |poethepoet_tasks_link| raw:: html
+
+   <a href="https://github.com/nat-n/poethepoet-tasks" target="_blank">poethepoet-tasks</a>
diff --git a/docs/guides/without_poetry.rst b/docs/guides/without_poetry.rst
index 775e025..0e5b191 100644
--- a/docs/guides/without_poetry.rst
+++ b/docs/guides/without_poetry.rst
@@ -36,7 +36,7 @@ As an alternative to toml, poethepoet configuration can also be provided via yam
 
 If ``pyproject.toml`` exists but does not contain the key prefix ``tool.poe`` then the search continues with `poe_tasks.toml`. If one of the listed ``poe_tasks.*`` files exist then the search is terminated, even if the file is empty.
 
-When config is loaded from a file other than ``pyproject.toml`` the ``tool.poe`` namespace for poe config is optional. So for example the following two poe_tasks.yaml files are equivalent and both valid:
+When config is loaded from a file other than ``pyproject.toml`` the ``tool.poe`` namespace for poe config is optional. So for example the following two ``poe_tasks.yaml`` files are equivalent and both valid:
 
 .. code-block:: yaml
   :caption: poe_tasks.yaml
diff --git a/docs/index.rst b/docs/index.rst
index 87079fd..74465e5 100644
--- a/docs/index.rst
+++ b/docs/index.rst
@@ -46,7 +46,7 @@ Top features
 
 |V| Straight forward declaration of project tasks in your pyproject.toml (or :doc:`poe_tasks.toml<./guides/without_poetry>`)
 
-|V| Tasks are run in poetry's virtualenv (or another env you specify)
+|V| Tasks are run in poetry, or uv's virtualenv (or another env you specify)
 
 |V| :ref:`Shell completion of task names<shell_completion>` (and global options too for zsh)
 
@@ -56,7 +56,7 @@ Top features
 
 |V| Concise commands with extra arguments passed to the task :sh:`poe [options] task [task_args]`
 
-|V| Easily :doc:`define CLI arguments<./guides/args_guide>` for your tasks
+|V| Easily :doc:`declare named CLI arguments<./guides/args_guide>` for your tasks
 
 |V| Tasks can specify and :ref:`reference environment variables<ref_env_vars>`, even without a shell
 
@@ -68,7 +68,9 @@ Top features
 
 |V| Can be :doc:`used as a library<./guides/library_guide>` to embed in other tools
 
-|V| Also works fine :doc:`without poetry<./guides/without_poetry>`
+|V| Tasks can be :doc:`defined in python packages<./guides/packaged_tasks>` for ease of reuse across projects
+
+|V| Also works fine as a :doc:`general purpose task runner<./guides/without_poetry>`
 
 
 Quick start
@@ -104,13 +106,13 @@ Quick start
 
 .. hint::
 
-  If you're using |poetry_link|, then poe will automatically use the poetry managed virtualenv to find executables and python libraries, without needing to use ``poetry run`` or ``poetry shell``.
+  If you're using |poetry_link| or |uv_link|, then poe will automatically use the managed virtualenv to find executables and python libraries, without needing to use ``poetry run``/``uv run``.
 
 
 Run poe from anywhere
 =====================
 
-By default poe will detect when you're inside a project with a pyproject.toml in the root. However if you want to run it from elsewhere then that is supported by using the :sh:`-C` option to specify an alternate location for the toml file. The task will run with the given location as the current working directory.
+By default poe will detect when you're inside a project with a pyproject.toml or poe_tasks file in the root. However if you want to run it from elsewhere then that is supported by using the :sh:`-C/--directory` option to specify an alternate location for the toml file. The task will run with the given location as the current working directory.
 
 In all cases the path to project root (where the pyproject.toml resides) will be available as :sh:`$POE_ROOT` within the command line and process. The variable :sh:`$POE_PWD` contains the original working directory from which poe was run.
 
@@ -124,3 +126,7 @@ Using this feature you can also define :doc:`global tasks<./guides/global_tasks>
 .. |poetry_link| raw:: html
 
    <a href="https://python-poetry.org/" target="_blank">poetry</a>
+
+.. |uv_link| raw:: html
+
+   <a href="https://docs.astral.sh/uv/" target="_blank">uv</a>
diff --git a/docs/tasks/task_types/cmd.rst b/docs/tasks/task_types/cmd.rst
index ea52659..8e87370 100644
--- a/docs/tasks/task_types/cmd.rst
+++ b/docs/tasks/task_types/cmd.rst
@@ -74,6 +74,10 @@ The ``:+`` or *alternate value* operator is especially useful in cases such as t
 In this example we declare a boolean argument with no default, so if the ``--arn-only`` flag is provided to the task then three additional CLI options will be included in the task content.
 
 
+.. note::
+
+   Unlike bash, glob patterns (``*``, ``?``, ``[...]``) inside ``:-`` and ``:+`` operator arguments are treated as literal text and are not expanded.
+
 Glob expansion
 ~~~~~~~~~~~~~~
 
diff --git a/poethepoet/app.py b/poethepoet/app.py
index bef3971..76c900c 100644
--- a/poethepoet/app.py
+++ b/poethepoet/app.py
@@ -52,6 +52,11 @@ class PoeThePoet:
         Optionally provide an alternative base environment for tasks to run with.
         If no mapping is provided then ``os.environ`` is used.
     :type env: dict, optional
+
+    :param suppress_args:
+        A sequence of identifiers for global arguments that should not be displayed in
+        the help message.
+    :type suppress_args: Sequence[str], optional
     """
 
     cwd: Path
@@ -69,6 +74,7 @@ class PoeThePoet:
         config_name: Optional[str] = None,
         program_name: str = "poe",
         env: Optional[Mapping[str, str]] = None,
+        suppress_args: Sequence[str] = ("legacy_project_root",),
     ):
         from .config import PoeConfig
         from .ui import PoeUi
@@ -84,7 +90,9 @@ class PoeThePoet:
             if isinstance(config, PoeConfig)
             else PoeConfig(cwd=self.cwd, table=config, config_name=config_name)
         )
-        self.ui = PoeUi(output=output, program_name=program_name)
+        self.ui = PoeUi(
+            output=output, program_name=program_name, suppress_args=suppress_args
+        )
         self._poetry_env_path = poetry_env_path
         self._env = env if env is not None else os.environ
 
@@ -252,7 +260,7 @@ class PoeThePoet:
         ] = {
             task_name: (
                 (
-                    content.get("help", ""),
+                    str(content.get("help", "")),
                     PoeTaskArgs.get_help_content(
                         content.get("args"), task_name, suppress_errors=bool(error)
                     ),
diff --git a/poethepoet/config/config.py b/poethepoet/config/config.py
index 5071add..604179e 100644
--- a/poethepoet/config/config.py
+++ b/poethepoet/config/config.py
@@ -3,9 +3,9 @@ from os import environ
 from pathlib import Path
 from typing import Any, Optional, Union
 
-from ..exceptions import ConfigValidationError, PoeException
+from ..exceptions import ConfigValidationError, ExpressionParseError, PoeException
 from .file import PoeConfigFile
-from .partition import ConfigPartition, IncludedConfig, ProjectConfig
+from .partition import ConfigPartition, IncludedConfig, PackagedConfig, ProjectConfig
 
 POE_DEBUG = environ.get("POE_DEBUG", "0") == "1"
 
@@ -13,6 +13,7 @@ POE_DEBUG = environ.get("POE_DEBUG", "0") == "1"
 class PoeConfig:
     _project_config: ProjectConfig
     _included_config: list[IncludedConfig]
+    _packaged_config: list[PackagedConfig]
 
     """
     The filenames to look for when loading config
@@ -31,6 +32,10 @@ class PoeConfig:
     This can be overridden, for example to align with poetry
     """
     _baseline_verbosity: int = 0
+    """
+    A global cache of raw configs derived from task packages
+    """
+    _packaged_config_cache: dict[tuple[str, ...], dict] = {}
 
     def __init__(
         self,
@@ -49,6 +54,7 @@ class PoeConfig:
             {"tool.poe": table or {}}, path=self._project_dir, strict=False
         )
         self._included_config = []
+        self._packaged_config = []
 
     def lookup_task(
         self, name: str
@@ -57,7 +63,7 @@ class PoeConfig:
         if task is not None:
             return task, self._project_config
 
-        for include in reversed(self._included_config):
+        for include in reversed((*self._packaged_config, *self._included_config)):
             task = include.get("tasks", {}).get(name, None)
             if task is not None:
                 return task, include
@@ -65,11 +71,14 @@ class PoeConfig:
         return None, None
 
     def partitions(self, included_first=True) -> Iterator[ConfigPartition]:
-        if not included_first:
-            yield self._project_config
-        yield from self._included_config
         if included_first:
+            yield from self._packaged_config
+            yield from self._included_config
+            yield self._project_config
+        else:
             yield self._project_config
+            yield from self._included_config
+            yield from self._packaged_config
 
     @property
     def executor(self) -> Mapping[str, Any]:
@@ -78,7 +87,7 @@ class PoeConfig:
     @property
     def task_names(self) -> Iterator[str]:
         result = list(self._project_config.get("tasks", {}).keys())
-        for config_part in self._included_config:
+        for config_part in self._included_config + self._packaged_config:
             for task_name in config_part.get("tasks", {}).keys():
                 # Don't use a set to dedup because we want to preserve task order
                 if task_name not in result:
@@ -88,8 +97,8 @@ class PoeConfig:
     @property
     def tasks(self) -> dict[str, Any]:
         result = dict(self._project_config.get("tasks", {}))
-        for config in self._included_config:
-            for task_name, task_def in config.get("tasks", {}).items():
+        for config_part in self._included_config + self._packaged_config:
+            for task_name, task_def in config_part.get("tasks", {}).items():
                 if task_name in result:
                     continue
                 result[task_name] = task_def
@@ -123,20 +132,21 @@ class PoeConfig:
         full_config = self._project_config.full_config
         return self._project_config.path.name == "pyproject.toml" and (
             "poetry" in full_config.get("tool", {})
+            # Fallbacks required to work out of the box with some poetry 2.0 projects
             or (
-                # Fallback required to work out of the box with some poetry 2.0 projects
                 full_config.get("build-system", {}).get("build-backend", "")
                 == "poetry.core.masonry.api"
             )
+            or self._project_config.path.parent.joinpath("poetry.lock").is_file()
         )
 
     @property
     def is_uv_project(self) -> bool:
         # Note: That it can happen that a uv managed project has no uv config
         #       In this case, this check would fail.
-        return (
-            self._project_config.path.name == "pyproject.toml"
-            and "uv" in self._project_config.full_config.get("tool", {})
+        return self._project_config.path.name == "pyproject.toml" and (
+            "uv" in self._project_config.full_config.get("tool", {})
+            or self._project_config.path.parent.joinpath("uv.lock").is_file()
         )
 
     @property
@@ -196,8 +206,128 @@ class PoeConfig:
                 )
 
         self._load_includes(strict=strict)
+        self._load_packages(strict=strict)
+
+    def _load_packages(self, strict: bool = True):
+        if not self._project_config.options.include_script:
+            return
+
+        import json
+
+        from ..helpers.script import parse_script_reference
+
+        def handle_error(msg: str, error: Union[Exception, None] = None):
+            if strict:
+                if error:
+                    raise PoeException(msg) from error
+                else:
+                    raise PoeException(msg)
+            elif POE_DEBUG:
+                print(" !", msg)
+
+        # Attempt to load tasks from each of the include_script
+        for include_script in self._project_config.options.include_script:
+            try:
+                target_module, function_call = parse_script_reference(
+                    include_script["script"], allowed_vars={"os", "sys", "environ"}
+                )
+            except ExpressionParseError as error:
+                raise PoeException(
+                    "Invalid configuration for include_script"
+                ) from error
+
+            invocation = ("$include_script$", include_script["script"])
+
+            if invocation not in self._packaged_config_cache:
+                from ..context import InitializationContext
+                from ..env.manager import EnvVarsManager
+
+                context = InitializationContext(config=self)
+                env = EnvVarsManager(self, base_env=environ)
+                executor = context.get_executor(
+                    invocation=invocation,
+                    env=env,
+                    working_dir=self._project_dir,
+                    executor_config=include_script.get("executor"),
+                    capture_stdout=True,
+                    resolve_python=True,
+                )
+
+                script = (
+                    "import os,sys,json;"
+                    "environ=os.environ;"
+                    "from importlib import import_module as _i;"
+                    f"sys.path.append('src');"
+                    "_o=sys.stdout;sys.stdout=sys.stderr;"
+                    f"_m = _i('{target_module}');"
+                    "sys.stdout=_o;"
+                    f"print(json.dumps(_m.{function_call.expression}));"
+                )
+                try:
+                    if POE_DEBUG:
+                        print(f" . Executing script for include_script {script!r}")
+                    subproc_code = executor.execute(("python", "-c", script))
+                except Exception as error:
+                    handle_error(
+                        "subprocess execution failed for configured include_script"
+                        f" {include_script['script']!r}",
+                        error,
+                    )
+                    continue
+
+                if subproc_code != 0:
+                    handle_error(
+                        "include_script subprocess returned non-zero for "
+                        f" {include_script['script']!r}",
+                    )
+                    continue
+
+                script_result = context.get_task_output(invocation)
+
+                try:
+                    parsed_result = json.loads(script_result)
+                    if isinstance(parsed_result, str):
+                        parsed_result = json.loads(parsed_result)
+                    self._packaged_config_cache[invocation] = parsed_result
+                except json.decoder.JSONDecodeError as error:
+                    handle_error(
+                        "Return value from include_script script must be valid json",
+                        error,
+                    )
+                    continue
+
+            try:
+                config_json = dict(self._packaged_config_cache[invocation])
+                config_path = Path(
+                    config_json.pop("config_path", self._project_config.path)
+                )
+                if config_json.get("tool", {}).get("poe"):
+                    pass
+                elif tool_poe := config_json.get("tool.poe"):
+                    config_json = {"tool": {"poe": tool_poe}}
+                else:
+                    config_json = {"tool": {"poe": config_json}}
+
+                if include_cwd := include_script.get("cwd"):
+                    config_cwd = self._project_dir.joinpath(include_cwd).resolve()
+                else:
+                    config_cwd = None
+
+                self._packaged_config.append(
+                    PackagedConfig(
+                        full_config=config_json,
+                        path=config_path,
+                        project_dir=self._project_dir,
+                        cwd=config_cwd,
+                        strict=strict,
+                    )
+                )
+            except (PoeException, KeyError) as error:
+                raise ConfigValidationError(
+                    f"Invalid content in loaded config from {target_module}"
+                ) from error
 
-    def _load_includes(self: "PoeConfig", strict: bool = True):
+    def _load_includes(self, strict: bool = True):
         # Attempt to load each of the included configs
         for include in self._project_config.options.include:
             include_path = self._resolve_include_path(include["path"])
@@ -221,7 +351,7 @@ class PoeConfig:
                         path=config_file.path,
                         project_dir=self._project_dir,
                         cwd=(
-                            self.project_dir.joinpath(include["cwd"]).resolve()
+                            self._project_dir.joinpath(include["cwd"]).resolve()
                             if include.get("cwd")
                             else None
                         ),
diff --git a/poethepoet/config/partition.py b/poethepoet/config/partition.py
index acc97cb..9fcc4b9 100644
--- a/poethepoet/config/partition.py
+++ b/poethepoet/config/partition.py
@@ -19,6 +19,15 @@ KNOWN_SHELL_INTERPRETERS = (
 )
 
 
+class IncludeScriptItem(TypedDict):
+    script: str
+    cwd: str
+    executor: Union[str, dict]
+
+
+IncludeScriptItem.__optional_keys__ = frozenset({"cwd", "executor"})
+
+
 class IncludeItem(TypedDict):
     path: str
     cwd: str
@@ -32,7 +41,7 @@ class ConfigPartition:
     full_config: Mapping[str, Any]
     poe_options: Mapping[str, Any]
     path: Path
-    project_dir: Path
+    _project_dir: Path
     _cwd: Optional[Path]
 
     ConfigOptions: type[PoeOptions]
@@ -63,11 +72,11 @@ class ConfigPartition:
         self.full_config = full_config
         self.path = path
         self._cwd = cwd
-        self.project_dir = project_dir or self.path.parent
+        self._project_dir = project_dir or self.path.parent
 
     @property
     def cwd(self):
-        return self._cwd or self.project_dir
+        return self._cwd or self._project_dir
 
     @property
     def config_dir(self):
@@ -92,6 +101,7 @@ class ProjectConfig(ConfigPartition):
         envfile: Union[str, Sequence[str]] = tuple()
         executor: Mapping[str, str] = MappingProxyType({"type": "auto"})
         include: Union[str, Sequence[str], Sequence[IncludeItem]] = tuple()
+        include_script: Union[str, Sequence[Union[str, IncludeScriptItem]]] = tuple()
         poetry_command: str = "poe"
         poetry_hooks: Mapping[str, str] = EmptyDict
         shell_interpreter: Union[str, Sequence[str]] = "posix"
@@ -107,37 +117,40 @@ class ProjectConfig(ConfigPartition):
             if isinstance(config, (list, tuple)):
                 raise ConfigValidationError("Expected ")
 
+            # Normalize executor option:
+            if (executor := config.get("executor")) and isinstance(executor, str):
+                config["executor"] = {"type": executor}
+
             # Normalize include option:
             # > Union[str, Sequence[str], Mapping[str, str]] => list[dict]
-            if "include" in config:
-                includes: Any = []
-                include_option = config.get("include", None)
-
-                if isinstance(include_option, (dict, str)):
-                    include_option = [include_option]
-
-                if isinstance(include_option, list):
-                    valid_keys = {"path", "cwd"}
-                    for include in include_option:
-                        if isinstance(include, str):
-                            includes.append({"path": include})
-                        elif (
-                            isinstance(include, dict)
-                            and include.get("path")
-                            and set(include.keys()) <= valid_keys
-                        ):
-                            includes.append(include)
-                        else:
-                            raise ConfigValidationError(
-                                f"Invalid item for the include option {include!r}",
-                                global_option="include",
-                            )
-                else:
-                    # Something is wrong, let option validation handle it
-                    includes = include_option
-
-                config = {**config, "include": includes}
-
+            if includes := config.get("include"):
+                if isinstance(includes, (dict, str)):
+                    includes = [includes]
+                if isinstance(includes, list):
+                    config["include"] = [
+                        {"path": item} if isinstance(item, str) else item
+                        for item in includes
+                    ]
+
+            # Normalize include_script option:
+            # > Union[str, Sequence[str], Sequence[IncludeScriptItem]]
+            #       => list[IncludeScriptItem]
+            if include_script := config.get("include_script"):
+                config["include_script"] = []
+                if not isinstance(include_script, list):
+                    include_script = [include_script]
+                for item in include_script:
+                    if isinstance(item, str):
+                        config["include_script"].append({"script": item})
+                    elif isinstance(executor_config := item.get("executor"), str):
+                        config["include_script"].append(
+                            {
+                                "script": item["script"],
+                                "executor": {"type": executor_config},
+                            }
+                        )
+                    else:
+                        config["include_script"].append(item)
             yield config
 
         def validate(self):
@@ -204,6 +217,11 @@ class ProjectConfig(ConfigPartition):
             # Validate executor config
             PoeExecutor.validate_config(self.executor)
 
+            # Validate include_script executor configs
+            for include_script in self.include_script:
+                if executor := include_script.get("executor"):
+                    PoeExecutor.validate_config(executor)
+
         @classmethod
         def validate_env(cls, env: Mapping[str, str]):
             # Validate env value
@@ -240,3 +258,23 @@ class IncludedConfig(ConfigPartition):
 
             # Apply same validation to env option as for the main config
             ProjectConfig.ConfigOptions.validate_env(self.env)
+
+
+class PackagedConfig(ConfigPartition):
+    class ConfigOptions(PoeOptions):
+        """
+        Options supported directly under tool.poe in config generated by a function call
+        """
+
+        env: Mapping[str, Union[str, EnvDefault]] = EmptyDict
+        envfile: Union[str, Sequence[str]] = tuple()
+        tasks: Mapping[str, Any] = EmptyDict
+
+        def validate(self):
+            """
+            Validation rules that don't require any extra context go here.
+            """
+            super().validate()
+
+            # Apply same validation to env option as for the main config
+            ProjectConfig.ConfigOptions.validate_env(self.env)
diff --git a/poethepoet/context.py b/poethepoet/context.py
index e119804..3e1aa6a 100644
--- a/poethepoet/context.py
+++ b/poethepoet/context.py
@@ -1,46 +1,78 @@
+from __future__ import annotations
+
+import os
 import re
-from collections.abc import Mapping
-from pathlib import Path
-from typing import TYPE_CHECKING, Any, Optional, Union
+from typing import TYPE_CHECKING, Any
 
 if TYPE_CHECKING:
+    from collections.abc import Mapping
+    from pathlib import Path
+
     from .config import PoeConfig
     from .env.manager import EnvVarsManager
     from .executor import PoeExecutor
     from .ui import PoeUi
 
 
+from typing import Protocol
+
+
+class ContextProtocol(Protocol):
+    config: PoeConfig
+    exec_cache: dict[str, Any]
+    ui: PoeUi | None
+
+    def save_task_output(self, invocation: tuple[str, ...], captured_stdout: bytes):
+        ...
+
+    def has_task_output(self, invocation: tuple[str, ...]) -> bool:
+        ...
+
+    def get_task_output(self, invocation: tuple[str, ...]) -> str:
+        ...
+
+    def get_executor(
+        self,
+        invocation: tuple[str, ...],
+        env: EnvVarsManager,
+        working_dir: Path,
+        *,
+        executor_config: Mapping[str, str] | None = None,
+        capture_stdout: str | bool = False,
+        resolve_python: bool = False,
+        delegate_dry_run: bool = False,
+    ) -> PoeExecutor:
+        ...
+
+
 class RunContext:
-    config: "PoeConfig"
-    ui: "PoeUi"
-    env: "EnvVarsManager"
+    config: PoeConfig
+    exec_cache: dict[str, Any]
+    ui: PoeUi | None
+    env: EnvVarsManager
     dry: bool
-    poe_active: Optional[str]
-    project_dir: Path
+    poe_active: str | None
     multistage: bool = False
-    exec_cache: dict[str, Any]
-    captured_stdout: dict[tuple[str, ...], str]
 
     def __init__(
         self,
-        config: "PoeConfig",
-        ui: "PoeUi",
+        config: PoeConfig,
+        ui: PoeUi,
         env: Mapping[str, str],
         dry: bool,
-        poe_active: Optional[str],
+        poe_active: str | None,
         multistage: bool = False,
-        cwd: Optional[Union[Path, str]] = None,
+        cwd: Path | str | None = None,
     ):
         from .env.manager import EnvVarsManager
 
         self.config = config
         self.ui = ui
-        self.project_dir = Path(config.project_dir)
         self.dry = dry
         self.poe_active = poe_active
         self.multistage = multistage
         self.exec_cache = {}
-        self.captured_stdout = {}
+        self._task_outputs = TaskOutputCache()
 
         # Init root EnvVarsManager
         self.env = EnvVarsManager(self.config, self.ui, base_env=env, cwd=cwd)
@@ -64,39 +96,25 @@ class RunContext:
         }
 
     def save_task_output(self, invocation: tuple[str, ...], captured_stdout: bytes):
-        """
-        Store the stdout data from a task so that it can be reused by other tasks
-        """
-        try:
-            self.captured_stdout[invocation] = captured_stdout.decode()
-        except UnicodeDecodeError:
-            # Attempt to recover in case a specific encoding is configured
-            io_encoding = self.env.get("PYTHONIOENCODING")
-            if io_encoding:
-                self.captured_stdout[invocation] = captured_stdout.decode(io_encoding)
-            else:
-                raise
+        self._task_outputs.save_task_output(invocation, captured_stdout)
 
-    def get_task_output(self, invocation: tuple[str, ...]):
-        """
-        Get the stored stdout data from a task so that it can be reused by other tasks
+    def has_task_output(self, invocation: tuple[str, ...]) -> bool:
+        return self._task_outputs.has_task_output(invocation)
 
-        New lines are replaced with whitespace similar to how unquoted command
-        interpolation works in bash.
-        """
-        return re.sub(r"\s+", " ", self.captured_stdout[invocation].strip("\r\n"))
+    def get_task_output(self, invocation: tuple[str, ...]) -> str:
+        return self._task_outputs.get_task_output(invocation)
 
     def get_executor(
         self,
         invocation: tuple[str, ...],
-        env: "EnvVarsManager",
+        env: EnvVarsManager,
         working_dir: Path,
         *,
-        executor_config: Optional[Mapping[str, str]] = None,
-        capture_stdout: Union[str, bool] = False,
+        executor_config: Mapping[str, str] | None = None,
+        capture_stdout: str | bool = False,
         resolve_python: bool = False,
         delegate_dry_run: bool = False,
-    ) -> "PoeExecutor":
+    ) -> PoeExecutor:
         """
         Get an Executor object for use with this invocation.
 
@@ -107,6 +125,7 @@ class RunContext:
         from .executor import PoeExecutor
 
         if not executor_config:
+            assert self.ui
             if self.ui["executor"]:
                 executor_config = {"type": self.ui["executor"]}
             else:
@@ -122,3 +141,91 @@ class RunContext:
             resolve_python=resolve_python,
             dry=False if delegate_dry_run else self.dry,
         )
+
+
+class InitializationContext:
+    exec_cache: dict[str, Any]
+    ui: PoeUi | None = None
+
+    def __init__(self, config: PoeConfig):
+        self._captured_stdout: dict[tuple[str, ...], str] = {}
+        self.config = config
+        self.exec_cache = {}
+        self._task_outputs = TaskOutputCache()
+
+    def save_task_output(self, invocation: tuple[str, ...], captured_stdout: bytes):
+        self._task_outputs.save_task_output(invocation, captured_stdout)
+
+    def has_task_output(self, invocation: tuple[str, ...]) -> bool:
+        return self._task_outputs.has_task_output(invocation)
+
+    def get_task_output(self, invocation: tuple[str, ...]) -> str:
+        return self._task_outputs.get_task_output(invocation)
+
+    def get_executor(
+        self,
+        invocation: tuple[str, ...],
+        env: EnvVarsManager,
+        working_dir: Path,
+        *,
+        executor_config: Mapping[str, str] | None = None,
+        capture_stdout: str | bool = False,
+        resolve_python: bool = False,
+        delegate_dry_run: bool = False,
+    ) -> PoeExecutor:
+        """
+        Get an Executor object for use with this invocation.
+
+        if delegate_dry_run is set then the task will always be executed and be
+        entrusted to not have any side effects when the dry-run flag is set.
+        """
+
+        from .executor import PoeExecutor
+
+        assert (
+            not delegate_dry_run
+        ), "delegate_dry_run option not valid on InitializationContext"
+
+        return PoeExecutor.get(
+            invocation=invocation,
+            context=self,
+            executor_config=executor_config or self.config.executor,
+            env=env,
+            working_dir=working_dir,
+            capture_stdout=capture_stdout,
+            resolve_python=resolve_python,
+            dry=False,
+        )
+
+
+class TaskOutputCache:
+    def __init__(self):
+        self._captured_stdout: dict[tuple[str, ...], str] = {}
+
+    def save_task_output(self, invocation: tuple[str, ...], captured_stdout: bytes):
+        """
+        Store the stdout data from a task so that it can be reused by other tasks
+        """
+        try:
+            self._captured_stdout[invocation] = captured_stdout.decode()
+        except UnicodeDecodeError:
+            # Attempt to recover in case a specific encoding is configured
+            if io_encoding := os.environ.get("PYTHONIOENCODING"):
+                self._captured_stdout[invocation] = captured_stdout.decode(io_encoding)
+            else:
+                raise
+
+    def has_task_output(self, invocation: tuple[str, ...]) -> bool:
+        """
+        Check whether there exists stored output for this invocation
+        """
+        return invocation in self._captured_stdout
+
+    def get_task_output(self, invocation: tuple[str, ...]) -> str:
+        """
+        Get the stored stdout data from a task so that it can be reused by other tasks
+
+        New lines are replaced with whitespace similar to how unquoted command
+        interpolation works in bash.
+        """
+        return re.sub(r"\s+", " ", self._captured_stdout[invocation].strip("\r\n"))
diff --git a/poethepoet/env/cache.py b/poethepoet/env/cache.py
index 815b223..d4aa0a4 100644
--- a/poethepoet/env/cache.py
+++ b/poethepoet/env/cache.py
@@ -7,7 +7,7 @@ from ..exceptions import ExecutionError
 if TYPE_CHECKING:
     from .ui import PoeUi
 
-POE_DEBUG = environ.get("POE_DEBUG", "0") == 1
+POE_DEBUG = environ.get("POE_DEBUG", "0") == "1"
 
 
 class EnvFileCache:
diff --git a/poethepoet/env/manager.py b/poethepoet/env/manager.py
index 250d3cb..85ee44f 100644
--- a/poethepoet/env/manager.py
+++ b/poethepoet/env/manager.py
@@ -1,29 +1,32 @@
+from __future__ import annotations
+
 import os
 from collections.abc import Mapping
-from pathlib import Path
-from typing import TYPE_CHECKING, Any, Optional, Union
+from typing import TYPE_CHECKING, Any
 
 from .template import apply_envvars_to_template
 
 if TYPE_CHECKING:
+    from pathlib import Path
+
     from .cache import EnvFileCache
     from .config import PoeConfig
     from .ui import PoeUi
 
 
 class EnvVarsManager(Mapping):
-    _config: "PoeConfig"
-    _ui: Optional["PoeUi"]
+    _config: PoeConfig
+    _ui: PoeUi | None
     _vars: dict[str, str]
-    envfiles: "EnvFileCache"
+    envfiles: EnvFileCache
 
     def __init__(  # TODO: check if we still need all these args!
         self,
-        config: "PoeConfig",
-        ui: Optional["PoeUi"],
-        parent_env: Optional["EnvVarsManager"] = None,
-        base_env: Optional[Mapping[str, str]] = None,
-        cwd: Optional[Union[Path, str]] = None,
+        config: PoeConfig,
+        ui: PoeUi | None = None,
+        parent_env: EnvVarsManager | None = None,
+        base_env: Mapping[str, str] | None = None,
+        cwd: Path | str | None = None,
     ):
         from ..helpers.git import GitRepo
         from .cache import EnvFileCache
@@ -62,7 +65,7 @@ class EnvVarsManager(Mapping):
     def __len__(self):
         return len(self._vars)
 
-    def get(self, key: Any, /, default: Any = None) -> Optional[str]:
+    def get(self, key: Any, /, default: Any = None) -> str | None:
         if key == "POE_GIT_DIR":
             # This is a special case environment variable that is only set if requested
             self._vars["POE_GIT_DIR"] = str(self._git_repo.path or "")
@@ -78,8 +81,8 @@ class EnvVarsManager(Mapping):
 
     def apply_env_config(
         self,
-        envfile: Optional[Union[str, list[str]]],
-        config_env: Optional[Mapping[str, Union[str, Mapping[str, str]]]],
+        envfile: str | list[str] | None,
+        config_env: Mapping[str, str | Mapping[str, str]] | None,
         config_dir: Path,
         config_working_dir: Path,
     ):
diff --git a/poethepoet/executor/base.py b/poethepoet/executor/base.py
index 06648e3..17f6ee1 100644
--- a/poethepoet/executor/base.py
+++ b/poethepoet/executor/base.py
@@ -1,14 +1,17 @@
+from __future__ import annotations
+
 import os
 import shutil
 import sys
-from collections.abc import Mapping, MutableMapping, Sequence
 from pathlib import Path
-from typing import TYPE_CHECKING, Any, ClassVar, Optional, Union
+from typing import TYPE_CHECKING, Any, ClassVar
 
 from ..exceptions import ConfigValidationError, ExecutionError, PoeException
 
 if TYPE_CHECKING:
-    from ..context import RunContext
+    from collections.abc import Mapping, MutableMapping, Sequence
+
+    from ..context import ContextProtocol
     from ..env.manager import EnvVarsManager
 
 
@@ -37,30 +40,31 @@ class PoeExecutor(metaclass=MetaPoeExecutor):
     A base class for poe task executors
     """
 
-    working_dir: Optional[Path]
+    working_dir: Path | None
 
-    __executor_types: ClassVar[dict[str, type["PoeExecutor"]]] = {}
-    __key__: ClassVar[Optional[str]] = None
+    __executor_types: ClassVar[dict[str, type[PoeExecutor]]] = {}
+    __key__: ClassVar[str | None] = None
 
     def __init__(
         self,
         invocation: tuple[str, ...],
-        context: "RunContext",
+        context: ContextProtocol,
         options: Mapping[str, str],
-        env: "EnvVarsManager",
+        env: EnvVarsManager,
         *,
-        working_dir: Optional[Path] = None,
-        capture_stdout: Union[str, bool] = False,
+        project_dir: Path | None = None,
+        working_dir: Path | None = None,
+        capture_stdout: str | bool = False,
         resolve_python: bool = False,
         dry: bool = False,
     ):
         self.invocation = invocation
         self.context = context
         self.options = options
-        self.working_dir = working_dir
+        self.working_dir = working_dir.resolve() if working_dir else None
         self.env = env
         self.capture_stdout = (
-            Path(self.context.config.project_dir).joinpath(
+            Path(project_dir or self.working_dir or ".").joinpath(
                 self.env.fill_template(capture_stdout)
             )
             if capture_stdout and isinstance(capture_stdout, str)
@@ -74,21 +78,21 @@ class PoeExecutor(metaclass=MetaPoeExecutor):
             print(f" . Initializing {self.__class__.__name__}")
 
     @classmethod
-    def works_with_context(cls, context: "RunContext") -> bool:
+    def works_with_context(cls, context: ContextProtocol) -> bool:
         return True
 
     @classmethod
     def get(
         cls,
         invocation: tuple[str, ...],
-        context: "RunContext",
+        context: ContextProtocol,
         executor_config: Mapping[str, str],
-        env: "EnvVarsManager",
-        working_dir: Optional[Path] = None,
-        capture_stdout: Union[str, bool] = False,
+        env: EnvVarsManager,
+        working_dir: Path | None = None,
+        capture_stdout: str | bool = False,
         resolve_python: bool = False,
         dry: bool = False,
-    ) -> "PoeExecutor":
+    ) -> PoeExecutor:
         """
         Create an executor.
         """
@@ -97,6 +101,7 @@ class PoeExecutor(metaclass=MetaPoeExecutor):
             context=context,
             options=executor_config,
             env=env,
+            project_dir=context.config.project_dir,
             working_dir=working_dir,
             capture_stdout=capture_stdout,
             resolve_python=resolve_python,
@@ -104,7 +109,7 @@ class PoeExecutor(metaclass=MetaPoeExecutor):
         )
 
     @classmethod
-    def _resolve_implementation(cls, context: "RunContext", executor_type: str):
+    def _resolve_implementation(cls, context: ContextProtocol, executor_type: str):
         """
         Resolve to an executor class, either as specified in the available config or
         by making some reasonable assumptions based on visible features of the
@@ -131,7 +136,7 @@ class PoeExecutor(metaclass=MetaPoeExecutor):
             return cls.__executor_types[executor_type]
 
     def execute(
-        self, cmd: Sequence[str], input: Optional[bytes] = None, use_exec: bool = False
+        self, cmd: Sequence[str], input: bytes | None = None, use_exec: bool = False
     ) -> int:
         """
         Execute the given cmd.
@@ -144,8 +149,8 @@ class PoeExecutor(metaclass=MetaPoeExecutor):
         self,
         cmd: Sequence[str],
         *,
-        input: Optional[bytes] = None,
-        env: Optional[Mapping[str, str]] = None,
+        input: bytes | None = None,
+        env: Mapping[str, str] | None = None,
         shell: bool = False,
         use_exec: bool = False,
     ) -> int:
@@ -188,7 +193,7 @@ class PoeExecutor(metaclass=MetaPoeExecutor):
         self,
         cmd: Sequence[str],
         *,
-        env: Optional[Mapping[str, str]] = None,
+        env: Mapping[str, str] | None = None,
     ):
         if self.dry:
             return 0
@@ -211,8 +216,8 @@ class PoeExecutor(metaclass=MetaPoeExecutor):
         self,
         cmd: Sequence[str],
         *,
-        input: Optional[bytes] = None,
-        env: Optional[Mapping[str, str]] = None,
+        input: bytes | None = None,
+        env: Mapping[str, str] | None = None,
         shell: bool = False,
     ) -> int:
         import signal
diff --git a/poethepoet/executor/poetry.py b/poethepoet/executor/poetry.py
index ef97943..a3e879e 100644
--- a/poethepoet/executor/poetry.py
+++ b/poethepoet/executor/poetry.py
@@ -1,13 +1,16 @@
-from collections.abc import Sequence
+from __future__ import annotations
+
 from os import environ
 from pathlib import Path
-from typing import TYPE_CHECKING, Optional
+from typing import TYPE_CHECKING
 
 from ..exceptions import ExecutionError
 from .base import PoeExecutor
 
 if TYPE_CHECKING:
-    from ..context import RunContext
+    from collections.abc import Sequence
+
+    from ..context import ContextProtocol
 
 
 class PoetryExecutor(PoeExecutor):
@@ -20,13 +23,13 @@ class PoetryExecutor(PoeExecutor):
     __options__: dict[str, type] = {}
 
     @classmethod
-    def works_with_context(cls, context: "RunContext") -> bool:
+    def works_with_context(cls, context: ContextProtocol) -> bool:
         if not context.config.is_poetry_project:
             return False
         return bool(cls._poetry_cmd_from_path())
 
     def execute(
-        self, cmd: Sequence[str], input: Optional[bytes] = None, use_exec: bool = False
+        self, cmd: Sequence[str], input: bytes | None = None, use_exec: bool = False
     ) -> int:
         """
         Execute the given cmd as a subprocess inside the poetry managed dev environment
@@ -103,9 +106,8 @@ class PoetryExecutor(PoeExecutor):
 
     @classmethod
     def _poetry_cmd(cls):
-        from_path = cls._poetry_cmd_from_path()
-        if from_path:
-            return str(Path(from_path).resolve())
+        if from_path := cls._poetry_cmd_from_path():
+            return from_path
 
         return "poetry"
 
diff --git a/poethepoet/executor/uv.py b/poethepoet/executor/uv.py
index 29874f8..6feba6c 100644
--- a/poethepoet/executor/uv.py
+++ b/poethepoet/executor/uv.py
@@ -1,11 +1,13 @@
-from collections.abc import Sequence
-from pathlib import Path
-from typing import TYPE_CHECKING, Optional
+from __future__ import annotations
+
+from typing import TYPE_CHECKING
 
 from .base import PoeExecutor
 
 if TYPE_CHECKING:
-    from ..context import RunContext
+    from collections.abc import Sequence
+
+    from ..context import ContextProtocol
 
 
 class UvExecutor(PoeExecutor):
@@ -18,13 +20,13 @@ class UvExecutor(PoeExecutor):
     __options__: dict[str, type] = {}
 
     @classmethod
-    def works_with_context(cls, context: "RunContext") -> bool:
+    def works_with_context(cls, context: ContextProtocol) -> bool:
         if not context.config.is_uv_project:
             return False
         return bool(cls._uv_cmd_from_path())
 
     def execute(
-        self, cmd: Sequence[str], input: Optional[bytes] = None, use_exec: bool = False
+        self, cmd: Sequence[str], input: bytes | None = None, use_exec: bool = False
     ) -> int:
         """
         Execute the given cmd as a subprocess inside the uv managed dev environment.
@@ -33,11 +35,16 @@ class UvExecutor(PoeExecutor):
         """
 
         uv_run_options = []
-        if self.context.ui.verbosity > 0:
+        if self.context.ui and self.context.ui.verbosity > 0:
             uv_run_options.append("-v")
-        elif self.context.ui.verbosity < 0:
+        elif self.context.ui and self.context.ui.verbosity < 0:
             uv_run_options.append("-q")
 
+        if self.working_dir:
+            # Explicitly set the working directory and project directory for uv
+            uv_run_options.append(f"--directory={self.working_dir}")
+            uv_run_options.append(f"--project={self.context.config.project_dir}")
+
         # Run this task with `uv run`
         return self._execute_cmd(
             (self._uv_cmd(), "run", *uv_run_options, *cmd),
@@ -47,9 +54,8 @@ class UvExecutor(PoeExecutor):
 
     @classmethod
     def _uv_cmd(cls):
-        from_path = cls._uv_cmd_from_path()
-        if from_path:
-            return str(Path(from_path).resolve())
+        if from_path := cls._uv_cmd_from_path():
+            return from_path
 
         return "uv"
 
diff --git a/poethepoet/executor/virtualenv.py b/poethepoet/executor/virtualenv.py
index 787bf33..9b5ccef 100644
--- a/poethepoet/executor/virtualenv.py
+++ b/poethepoet/executor/virtualenv.py
@@ -1,11 +1,14 @@
-from collections.abc import Sequence
-from typing import TYPE_CHECKING, Any, Optional
+from __future__ import annotations
+
+from typing import TYPE_CHECKING, Any
 
 from ..exceptions import ConfigValidationError, ExecutionError
 from .base import PoeExecutor
 
 if TYPE_CHECKING:
-    from ..context import RunContext
+    from collections.abc import Sequence
+
+    from ..context import ContextProtocol
     from ..virtualenv import Virtualenv
 
 
@@ -18,13 +21,13 @@ class VirtualenvExecutor(PoeExecutor):
     __options__: dict[str, type] = {"location": str}
 
     @classmethod
-    def works_with_context(cls, context: "RunContext") -> bool:
+    def works_with_context(cls, context: ContextProtocol) -> bool:
         from ..virtualenv import Virtualenv
 
-        return Virtualenv.detect(context.project_dir)
+        return Virtualenv.detect(context.config.project_dir)
 
     def execute(
-        self, cmd: Sequence[str], input: Optional[bytes] = None, use_exec: bool = False
+        self, cmd: Sequence[str], input: bytes | None = None, use_exec: bool = False
     ) -> int:
         """
         Execute the given cmd as a subprocess inside the configured virtualenv
@@ -47,24 +50,24 @@ class VirtualenvExecutor(PoeExecutor):
             f"executable {cmd[0]!r} could not be found{error_context}"
         ) from error
 
-    def _resolve_virtualenv(self) -> "Virtualenv":
+    def _resolve_virtualenv(self) -> Virtualenv:
         from ..virtualenv import Virtualenv
 
+        project_dir = self.context.config.project_dir
+
         if "location" in self.options:
-            venv = Virtualenv(
-                self.context.project_dir.joinpath(self.options["location"])
-            )
+            venv = Virtualenv(project_dir.joinpath(self.options["location"]))
             if venv.valid():
                 return venv
             raise ExecutionError(
                 f"Could not find valid virtualenv at configured location: {venv.path}"
             )
 
-        venv = Virtualenv(self.context.project_dir.joinpath("venv"))
+        venv = Virtualenv(project_dir.joinpath("venv"))
         if venv.valid():
             return venv
 
-        hidden_venv = Virtualenv(self.context.project_dir.joinpath(".venv"))
+        hidden_venv = Virtualenv(project_dir.joinpath(".venv"))
         if hidden_venv.valid():
             return hidden_venv
 
diff --git a/poethepoet/helpers/command/__init__.py b/poethepoet/helpers/command/__init__.py
index 0925c2d..abce619 100644
--- a/poethepoet/helpers/command/__init__.py
+++ b/poethepoet/helpers/command/__init__.py
@@ -31,7 +31,14 @@ def resolve_command_tokens(
     patterns that are not escaped or quoted. In case there are glob patterns in the
     token, any escaped glob characters will have been escaped with [].
     """
-    from .ast import Glob, ParamArgument, ParamExpansion, ParseConfig, PythonGlob
+    from .ast import (
+        Glob,
+        ParamArgument,
+        ParamExpansion,
+        ParseConfig,
+        PythonGlob,
+        WhitespaceText,
+    )
 
     if not config:
         config = ParseConfig(substitute_nodes={Glob: PythonGlob})
@@ -57,33 +64,109 @@ def resolve_command_tokens(
         return (token, includes_glob)
 
     def resolve_param_argument(argument: ParamArgument, env: Mapping[str, str]):
-        token_parts = []
+        """
+        Flatten a ParamArgument to a string, discarding quote structure.
+        Used when the result will be placed in an already-quoted context.
+        """
+        parts: list[str] = []
         for segment in argument.segments:
             for element in segment:
                 if isinstance(element, ParamExpansion):
-                    token_parts.append(resolve_param_value(element, env))
+                    result = resolve_param_value(element, env)
+                    if isinstance(result, ParamArgument):
+                        parts.append(resolve_param_argument(result, env))
+                    else:
+                        parts.append(result)
                 else:
-                    token_parts.append(element.content)
+                    parts.append(element.content)
 
-        return "".join(token_parts)
+        return "".join(parts)
 
-    def resolve_param_value(element: ParamExpansion, env: Mapping[str, str]):
+    def resolve_param_value(
+        element: ParamExpansion, env: Mapping[str, str]
+    ) -> str | ParamArgument:
+        """
+        Returns a plain string for simple variable values, or a ParamArgument
+        when an operation's argument should be processed with its quoting intact.
+        """
         param_value = env.get(element.param_name, "")
 
         if element.operation:
             if param_value:
                 if element.operation.operator == ":+":
-                    # apply 'alternate value' operation
-                    param_value = resolve_param_argument(
-                        element.operation.argument, env
-                    )
-
+                    return element.operation.argument
             elif element.operation.operator == ":-":
-                # apply 'default value' operation
-                param_value = resolve_param_argument(element.operation.argument, env)
+                return element.operation.argument
 
         return param_value
 
+    def resolve_argument_tokens(
+        argument: ParamArgument,
+        env: Mapping[str, str],
+        token_parts: list[tuple[str, bool]],
+    ) -> Iterator[tuple[str, bool]]:
+        """
+        Process a ParamArgument's segments inline, respecting quoting.
+        Quoted segments are not word-split; unquoted WhitespaceText causes
+        word breaks.
+        """
+        for arg_segment in argument.segments:
+            if arg_segment.is_quoted:
+                for element in arg_segment:
+                    if isinstance(element, ParamExpansion):
+                        result = resolve_param_value(element, env)
+                        if isinstance(result, ParamArgument):
+                            flat = resolve_param_argument(result, env)
+                            if flat:
+                                token_parts.append((flat, False))
+                        elif result:
+                            token_parts.append((result, False))
+                    else:
+                        token_parts.append((element.content, False))
+            else:
+                for element in arg_segment:
+                    if isinstance(element, WhitespaceText):
+                        if token_parts:
+                            yield finalize_token(token_parts)
+                    elif isinstance(element, ParamExpansion):
+                        result = resolve_param_value(element, env)
+                        if isinstance(result, ParamArgument):
+                            yield from resolve_argument_tokens(result, env, token_parts)
+                        elif result:
+                            yield from _emit_unquoted_param_value(result, token_parts)
+                    else:
+                        token_parts.append((element.content, False))
+
+    def _emit_unquoted_param_value(
+        param_value: str,
+        token_parts: list[tuple[str, bool]],
+    ) -> Iterator[tuple[str, bool]]:
+        """
+        Handle an unquoted plain string param value: word-split on whitespace
+        and check for glob patterns.
+        """
+        if param_value.isspace():
+            if token_parts:
+                yield finalize_token(token_parts)
+            return
+
+        if param_value[0].isspace() and token_parts:
+            yield finalize_token(token_parts)
+
+        param_words = (
+            (word, bool(glob_pattern.search(word))) for word in param_value.split()
+        )
+
+        token_parts.append(next(param_words))
+
+        for param_word in param_words:
+            if token_parts:
+                yield finalize_token(token_parts)
+            token_parts.append(param_word)
+
+        if param_value[-1].isspace() and token_parts:
+            yield finalize_token(token_parts)
+
     for line in lines:
         # Ignore line breaks, assuming they're only due to comments
         for word in line:
@@ -95,41 +178,30 @@ def resolve_command_tokens(
             for segment in word:
                 for element in segment:
                     if isinstance(element, ParamExpansion):
-                        param_value = resolve_param_value(element, env)
+                        result = resolve_param_value(element, env)
+
+                        if isinstance(result, ParamArgument) and not segment.is_quoted:
+                            # In unquoted context, process argument
+                            # segments inline to preserve quoting
+                            yield from resolve_argument_tokens(result, env, token_parts)
+                            continue
+
+                        # Flatten ParamArgument to string for quoted
+                        # contexts (or use the string value directly)
+                        param_value = (
+                            resolve_param_argument(result, env)
+                            if isinstance(result, ParamArgument)
+                            else result
+                        )
                         if not param_value:
-                            # Empty param value has no effect
                             continue
                         if segment.is_quoted:
                             token_parts.append((param_value, False))
-                        elif param_value.isspace():
-                            # collapse whitespace value
-                            token_parts.append((" ", False))
                         else:
-                            # If the the param expansion it not quoted then:
-                            # - Whitespace inside a substituted param value results in
-                            #  a word break, regardless of quotes or backslashes
-                            # - glob patterns should be evaluated
-
-                            if param_value[0].isspace() and token_parts:
-                                # param_value starts with a word break
-                                yield finalize_token(token_parts)
-
-                            param_words = (
-                                (word, bool(glob_pattern.search(word)))
-                                for word in param_value.split()
+                            yield from _emit_unquoted_param_value(
+                                param_value, token_parts
                             )
 
-                            token_parts.append(next(param_words))
-
-                            for param_word in param_words:
-                                if token_parts:
-                                    yield finalize_token(token_parts)
-                                token_parts.append(param_word)
-
-                            if param_value[-1].isspace() and token_parts:
-                                # param_value ends with a word break
-                                yield finalize_token(token_parts)
-
                     elif isinstance(element, Glob):
                         token_parts.append((element.content, True))
 
diff --git a/poethepoet/helpers/script.py b/poethepoet/helpers/script.py
new file mode 100644
index 0000000..efbd119
--- /dev/null
+++ b/poethepoet/helpers/script.py
@@ -0,0 +1,58 @@
+from __future__ import annotations
+
+from typing import TYPE_CHECKING, Any
+
+from ..exceptions import ExpressionParseError
+
+if TYPE_CHECKING:
+    from collections.abc import Container
+
+    from ..helpers.python import FunctionCall
+
+
+def parse_script_reference(
+    script_ref: str,
+    parsed_args: dict[str, Any] | None = None,
+    allowed_vars: Container[str] = tuple(),
+) -> tuple[str, FunctionCall]:
+    """
+    Parses a script reference string and returns the module name and function call.
+
+    Args:
+        script_ref (str): A string representing the script reference, expected to
+            include a module and function call (e.g., "module:function(arg1, arg2)").
+        parsed_args (dict[str, Any] | None): A dictionary of arguments that have been
+            parsed and are available for substitution.
+        allowed_vars (Container[str]): An optional collection of variable names that may
+            be referenced within the function call.
+
+    Returns:
+        tuple[str, FunctionCall]: A tuple containing:
+            - The module name as a string.
+            - A `FunctionCall` object representing the parsed function invocation.
+
+    Raises:
+        ExpressionParseError: If the script reference is contains invalid syntax or
+        references variables that are not in scope.
+    """
+
+    from ..helpers.python import FunctionCall
+
+    try:
+        target_module, target_ref = script_ref.strip().split(":", 1)
+    except ValueError:
+        raise ExpressionParseError(f"Invalid script reference: {script_ref.strip()!r}")
+
+    if target_ref.isidentifier():
+        if parsed_args:
+            function_call = FunctionCall(f"{target_ref}(**({parsed_args}))", target_ref)
+        else:
+            function_call = FunctionCall(f"{target_ref}()", target_ref)
+    else:
+        function_call = FunctionCall.parse(
+            source=target_ref,
+            arguments=set(parsed_args or tuple()),
+            allowed_vars=allowed_vars,
+        )
+
+    return target_module, function_call
diff --git a/poethepoet/plugin.py b/poethepoet/plugin.py
index c3ba904..632df8c 100644
--- a/poethepoet/plugin.py
+++ b/poethepoet/plugin.py
@@ -74,6 +74,15 @@ class PoeCommand(Command):
             output=io.output.stream,
             poetry_env_path=poetry_env_path,
             program_name=f"poetry {cls.command_prefix}",
+            # Suppress global CLI options on poe that don't work as a poetry plugin
+            suppress_args=(
+                "help",
+                "version",
+                "verbosity",
+                "project_root",
+                "legacy_project_root",
+                "ansi",
+            ),
         )
 
 
@@ -124,6 +133,8 @@ class PoetryPlugin(ApplicationPlugin):
                         f"Poe task {task_name!r} conflicts with a poetry command. "
                         "Please rename the task or the configure a command prefix."
                     )
+                if task_name.startswith("_"):
+                    continue
                 self._register_command(application, poe_config, task_name, task)
         else:
             self._register_command(
@@ -302,5 +313,5 @@ def _index_of_first_non_option(tokens: list[str]):
         if token[0] != "-" and previous_token not in options_with_args:
             return index
         previous_token = token
-    else:
-        return len(tokens)
+
+    return len(tokens)
diff --git a/poethepoet/task/base.py b/poethepoet/task/base.py
index d8b6d72..16802c5 100644
--- a/poethepoet/task/base.py
+++ b/poethepoet/task/base.py
@@ -402,6 +402,13 @@ class PoeTask(metaclass=MetaPoeTask):
     def get_parsed_arguments(
         self, env: "EnvVarsManager"
     ) -> tuple[dict[str, str], tuple[str, ...]]:
+        """
+        Returns a dict of parsed arguments, and a list extra arguments.
+
+        If no args are defined for the task then all arguments are "extra",
+        otherwise its only arguments passed after a `--`.
+        """
+
         if self._parsed_args is None:
             all_args = self.invocation[1:]
 
diff --git a/poethepoet/task/cmd.py b/poethepoet/task/cmd.py
index 538f9db..42bc036 100644
--- a/poethepoet/task/cmd.py
+++ b/poethepoet/task/cmd.py
@@ -53,13 +53,14 @@ class CmdTask(PoeTask):
         named_arg_values, extra_args = self.get_parsed_arguments(env)
         env.update(named_arg_values)
 
+        executor = self._get_executor(context, env)
+        env.update({"POE_ACTIVE": executor.__key__})
+
         cmd = (*self._resolve_commandline(context, env), *extra_args)
 
         self._print_action(shlex.join(cmd), context.dry)
 
-        return self._get_executor(context, env).execute(
-            cmd, use_exec=self.spec.options.get("use_exec", False)
-        )
+        return executor.execute(cmd, use_exec=self.spec.options.get("use_exec", False))
 
     def _resolve_commandline(self, context: "RunContext", env: "EnvVarsManager"):
         from ..helpers.command import parse_poe_cmd, resolve_command_tokens
diff --git a/poethepoet/task/expr.py b/poethepoet/task/expr.py
index 35ef74b..43438d2 100644
--- a/poethepoet/task/expr.py
+++ b/poethepoet/task/expr.py
@@ -95,7 +95,7 @@ class ExprTask(PoeTask):
         self,
         args: Optional[dict[str, Any]],
         env: "EnvVarsManager",
-        imports=Iterable[str],
+        imports: Iterable[str],
     ) -> tuple[str, dict[str, str]]:
         """
         Returns the expression to evaluate and the subset of env vars that it references
diff --git a/poethepoet/task/script.py b/poethepoet/task/script.py
index 6d76d7c..4680d5e 100644
--- a/poethepoet/task/script.py
+++ b/poethepoet/task/script.py
@@ -1,14 +1,14 @@
 import shlex
-from typing import TYPE_CHECKING, Any, Optional
+from typing import TYPE_CHECKING
 
 from ..exceptions import ConfigValidationError, ExpressionParseError
+from ..helpers.script import parse_script_reference
 from .base import PoeTask
 
 if TYPE_CHECKING:
     from ..config import PoeConfig
     from ..context import RunContext
     from ..env.manager import EnvVarsManager
-    from ..helpers.python import FunctionCall
     from .base import TaskSpecFactory
 
 
@@ -65,9 +65,13 @@ class ScriptTask(PoeTask):
         named_arg_values, extra_args = self.get_parsed_arguments(env)
         env.update(named_arg_values)
 
-        # TODO: do something about extra_args, error?
+        # TODO: do something about extra_args, like raise an error?
 
-        target_module, function_call = self.parse_content(named_arg_values)
+        target_module, function_call = parse_script_reference(
+            self.spec.content,
+            named_arg_values,
+            allowed_vars={"sys", "os", "environ", "_dry_run"},
+        )
         function_ref = function_call.function_ref
 
         argv = [
@@ -84,8 +88,8 @@ class ScriptTask(PoeTask):
         script = [
             "import asyncio,os,sys;",
             "from inspect import iscoroutinefunction as _c;",
-            "from os import environ;",
             "from importlib import import_module as _i;",
+            "environ = os.environ;",
             f"_dry_run = {'True' if dry_run else 'False'};" if has_dry_run_ref else "",
             f"sys.argv = {argv!r}; sys.path.append('src');",
             f"{format_class(named_arg_values)}",
@@ -106,36 +110,3 @@ class ScriptTask(PoeTask):
         return self._get_executor(
             context, env, delegate_dry_run=has_dry_run_ref, resolve_python=True
         ).execute(cmd, use_exec=self.spec.options.get("use_exec", False))
-
-    def parse_content(
-        self, args: Optional[dict[str, Any]]
-    ) -> tuple[str, "FunctionCall"]:
-        """
-        Returns the module to load, and the function call to execute.
-
-        Will raise an exception if the function call contains invalid syntax or
-        references variables that are not in scope.
-        """
-
-        from ..helpers.python import FunctionCall
-
-        try:
-            target_module, target_ref = self.spec.content.strip().split(":", 1)
-        except ValueError:
-            raise ExpressionParseError(
-                f"Invalid task content: {self.spec.content.strip()!r}"
-            )
-
-        if target_ref.isidentifier():
-            if args:
-                function_call = FunctionCall(f"{target_ref}(**({args}))", target_ref)
-            else:
-                function_call = FunctionCall(f"{target_ref}()", target_ref)
-        else:
-            function_call = FunctionCall.parse(
-                source=target_ref,
-                arguments=set(args or tuple()),
-                allowed_vars={"sys", "os", "environ", "_dry_run"},
-            )
-
-        return target_module, function_call
diff --git a/poethepoet/task/shell.py b/poethepoet/task/shell.py
index 2338dd5..2d322b0 100644
--- a/poethepoet/task/shell.py
+++ b/poethepoet/task/shell.py
@@ -1,6 +1,7 @@
 import re
 from collections.abc import Sequence
 from os import environ
+from pathlib import Path
 from typing import TYPE_CHECKING, Optional, Union
 
 from ..exceptions import ConfigValidationError, PoeException
@@ -141,6 +142,12 @@ class ShellTask(PoeTask):
             if result is None and self._is_windows:
                 result = which(f"{prog_files}\\Git\\bin\\sh.exe")
 
+                if result is None and (git_path_str := which("git")) is not None:
+                    # Check if sh.exe can be found relative to the git executable
+                    # in case git is installed at a non-standard location.
+                    git_path = Path(git_path_str)
+                    if (sh_path := git_path.parent.parent / "bin" / "sh.exe").exists():
+                        result = str(sh_path)
         elif interpreter == "bash":
             if self._is_windows:
                 # Specifically look for git bash on windows as the preferred option
diff --git a/poethepoet/task/switch.py b/poethepoet/task/switch.py
index 8675de3..ced1242 100644
--- a/poethepoet/task/switch.py
+++ b/poethepoet/task/switch.py
@@ -88,8 +88,12 @@ class SwitchTask(PoeTask):
             for switch_item in task_def["switch"]:
                 case_task_def = dict(switch_item, args=switch_args)
                 case = case_task_def.pop("case", DEFAULT_CASE)
-                case_tuple = tuple(case) if isinstance(case, list) else (case,)
-                case_task_index = ",".join(str(value) for value in case_tuple)
+                case_tuple = (
+                    tuple(str(value) for value in case)
+                    if isinstance(case, list)
+                    else (str(case),)
+                )
+                case_task_index = ",".join(case_tuple)
                 case_task_specs.append(
                     (
                         case_tuple,
diff --git a/poethepoet/ui.py b/poethepoet/ui.py
index f2201a3..da0893d 100644
--- a/poethepoet/ui.py
+++ b/poethepoet/ui.py
@@ -37,10 +37,16 @@ class PoeUi:
     args: "Namespace"
     _color: "Pastel"
 
-    def __init__(self, output: IO, program_name: str = "poe"):
+    def __init__(
+        self,
+        output: IO,
+        program_name: str = "poe",
+        suppress_args: Sequence[str] = ("legacy_project_root",),
+    ):
         self.output = output
         self.program_name = program_name
         self._init_colors()
+        self.suppress_args = set(suppress_args)
 
     def _init_colors(self):
         from pastel import Pastel
@@ -65,11 +71,16 @@ class PoeUi:
 
         parser = argparse.ArgumentParser(
             prog=self.program_name,
-            description="Poe the Poet: A task runner that works well with poetry.",
+            description="Poe the Poet: A task runner that works well with poetry or uv",
             add_help=False,
             allow_abbrev=False,
         )
 
+        def maybe_suppress(arg_name: str, help_text: str):
+            if arg_name in self.suppress_args:
+                return argparse.SUPPRESS
+            return help_text
+
         parser.add_argument(
             "-h",
             "--help",
@@ -77,7 +88,9 @@ class PoeUi:
             metavar="TASK",
             nargs="?",
             default=...,
-            help="Show this help page and exit, optionally supply a task.",
+            help=maybe_suppress(
+                "help", "Show this help page and exit, optionally supply a task."
+            ),
         )
 
         parser.add_argument(
@@ -85,7 +98,7 @@ class PoeUi:
             dest="version",
             action="store_true",
             default=False,
-            help="Print the version and exit",
+            help=maybe_suppress("version", "Print the version and exit"),
         )
 
         parser.add_argument(
@@ -94,7 +107,7 @@ class PoeUi:
             dest="increase_verbosity",
             action="count",
             default=0,
-            help="Increase command output (repeatable)",
+            help=maybe_suppress("verbosity", "Increase command output (repeatable)"),
         )
 
         parser.add_argument(
@@ -103,7 +116,7 @@ class PoeUi:
             dest="decrease_verbosity",
             action="count",
             default=0,
-            help="Decrease command output (repeatable)",
+            help=maybe_suppress("verbosity", "Decrease command output (repeatable)"),
         )
 
         parser.add_argument(
@@ -112,7 +125,9 @@ class PoeUi:
             dest="dry_run",
             action="store_true",
             default=False,
-            help="Print the task contents but don't actually run it",
+            help=maybe_suppress(
+                "dry_run", "Print the task contents but don't actually run it"
+            ),
         )
 
         parser.add_argument(
@@ -122,7 +137,9 @@ class PoeUi:
             metavar="PATH",
             type=str,
             default=os.environ.get("POE_PROJECT_DIR", None),
-            help="Specify where to find the pyproject.toml",
+            help=maybe_suppress(
+                "project_root", "Specify where to find the pyproject.toml"
+            ),
         )
 
         parser.add_argument(
@@ -132,7 +149,7 @@ class PoeUi:
             metavar="EXECUTOR",
             type=str,
             default="",
-            help="Override the default task executor",
+            help=maybe_suppress("executor", "Override the default task executor"),
         )
 
         # legacy --root parameter, keep for backwards compatibility but help output is
@@ -143,7 +160,9 @@ class PoeUi:
             metavar="PATH",
             type=str,
             default=None,
-            help=argparse.SUPPRESS,
+            help=maybe_suppress(
+                "legacy_project_root", "Specify where to find the pyproject.toml"
+            ),
         )
 
         ansi_group = parser.add_mutually_exclusive_group()
@@ -152,14 +171,14 @@ class PoeUi:
             dest="ansi",
             action="store_true",
             default=STDOUT_ANSI_SUPPORT,
-            help="Force enable ANSI output",
+            help=maybe_suppress("ansi", "Force enable ANSI output"),
         )
         ansi_group.add_argument(
             "--no-ansi",
             dest="ansi",
             action="store_false",
             default=STDOUT_ANSI_SUPPORT,
-            help="Force disable ANSI output",
+            help=maybe_suppress("ansi", "Force disable ANSI output"),
         )
 
         parser.add_argument("task", default=tuple(), nargs=argparse.REMAINDER)
@@ -183,21 +202,19 @@ class PoeUi:
         info: Optional[str] = None,
         error: Optional[PoeException] = None,
     ):
-        # TODO: See if this can be done nicely with a custom HelpFormatter
-
         # Ignore verbosity mode if help flag is set
         help_flag_set = self["help"] is None
         help_single_task = self["help"] if isinstance(self["help"], str) else None
         verbosity = 0 if help_flag_set else self.verbosity
 
+        # If there's no error and verbosity wasn't explicitly decreased for this call,
+        # then ensure we still print help
+        if not error and self.verbosity < 0 and not self["decrease_verbosity"]:
+            verbosity = 0
+
         result: list[Union[str, Sequence[str]]] = []
         if verbosity >= 0 and not help_single_task:
-            result.append(
-                (
-                    "Poe the Poet - A task runner that works well with poetry.",
-                    f"version <em>{__version__}</em>",
-                )
-            )
+            result.append((f"<h2>Poe the Poet</h2> (version <em>{__version__}</em>)",))
 
         if info:
             result.append(f"{f'<em2>Result: {info}</em2>'}")
diff --git a/pyproject.toml b/pyproject.toml
index 64cb707..16146b7 100644
--- a/pyproject.toml
+++ b/pyproject.toml
@@ -87,6 +87,7 @@ help   = "Remove generated files"
 script = """
   poethepoet.scripts:rm(
     ".coverage",
+    ".ruff_cache",
     ".mypy_cache",
     ".pytest_cache",
     "./**/__pycache__",
@@ -198,6 +199,9 @@ ignore  = [
 ]
 fixable = ["E", "F", "I"]
 
+[tool.uv.workspace]
+members = ["tests/fixtures/task_package"]
+
 
 [build-system]
 requires      = ["poetry-core>=2.0.0,<3.0.0"]
COLLAB_REFERENCE_PATCH_EOF
