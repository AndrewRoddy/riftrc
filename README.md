# This is my rift.rc file
rift is a vim like text editor
.riftrc files aren't supported yet so I have mine implemented as a lua plugin


This is what I use to load the plugin, this is not advice, this code is insecure
```
local dir = _rift_current_plugin_file:match("(.*)/[^/]+$")
package.path = package.path .. ';' .. dir .. '/?.lua;' .. dir .. '/?/init.lua'

require("riftrc")
```
