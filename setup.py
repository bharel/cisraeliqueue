from setuptools import setup, Extension
from Cython.Build import cythonize
from Cython.Compiler import Options

# These are optional
Options.docstrings = True
Options.annotate = True

# Modules to be compiled and include_dirs when necessary
extensions = [
    # Extension(
    #     "pyctmctree.inpyranoid_c",
    #     ["src/pyctmctree/inpyranoid_c.pyx"],
    # ),
    Extension(
        "israeliqueue",
        ["israeliqueue/__init__.pyx"],
        # define_macros=[
        #     ("Py_LIMITED_API", 0x030C0000),
        # ],
        # py_limited_api=True
    ),
]


# This is the function that is executed
setup(
    name='israeliqueue',  # Required

    # A list of compiler Directives is available at
    # https://cython.readthedocs.io/en/latest/src/userguide/source_files_and_compilation.html#compiler-directives

    # external to be compiled
    ext_modules=cythonize(
        extensions,
    ),
)
