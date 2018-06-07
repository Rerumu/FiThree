# FiThree
FiThree is a Lua 5.3 vm implementation using Lua.
It is designed to mirror the behaviour of lvm.c in the source for the most part, and some of the lundump.c functionality.
Some minor changes are present, such as the fact that it will attempt to match the endianness of the bytecode if possible.
Please note that this is prone to have bugs, and is not a perfect mirror, but please report any inconvenience (bug) you find.

Dependencies:
* Any functional bit32 library
* A version of Lua 5.1 or higher

The bit32 library can be a Lua implementation or built in C. For best results, use LuaJIT, as it comes with a built in library for it and supports this without any necessary modifications.
