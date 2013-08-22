server-status
=============

mod_lua version of the Apache httpd's mod_status using dynamic charts

## Installing ##
First, install mod_lua

Then add the following to your httpd.conf in the appropriate VirtualHost:

    LuaMapHandler ^/server-status$ /path/to/server-status.lua
    