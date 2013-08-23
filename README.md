server-status
=============

mod_lua version of the Apache httpd's mod_status using dynamic charts

## What does it to? ##
Take a look at http://apaste.info/server-status to see what it does :)

## Installing ##
First, install mod_lua (you can enable this during configure time with --enable-lua)

Then add the following to your httpd.conf in the appropriate VirtualHost:

    LuaMapHandler ^/server-status$ /path/to/server-status.lua
    
