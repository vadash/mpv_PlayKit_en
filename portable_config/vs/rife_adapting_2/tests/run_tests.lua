-- Test runner for rife_core
package.path = package.path .. ';../?.lua;./?.lua'

local lu = require('luaunit')

-- Import test modules
require('test_rife_core')

-- Run tests
os.exit(lu.LuaUnit.run())
