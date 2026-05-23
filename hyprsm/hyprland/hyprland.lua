-- Add the trans-lua directory to the Lua module path
package.path = package.path .. ";" .. os.getenv("HOME") .. "/.config/hypr/modules/?.lua"

-- Import all files in exact recommended execution order
require("env")
require("monitor")
require("input")
require("look-and-feel")
require("binds")
require("windowrule")
require("auto-start")
require("misc")

