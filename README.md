server-status
=============

`mod_lua` version of the Apache httpd's mod_status using dynamic charts
![screenshot](http://www.humbedooh.com/images/serverstatus.png?foo)

## What does it to? ##
This script is an extended version of the known mod_status statistics page for httpd.
It uses the Google Chart API to visualize many of the elements that are sometimes hard 
to properly diagnose using plain text information.

Take a look at http://apaste.info/server-status.lua to see how it works.

## Requirements ##
* Apache httpd 2.4.6 or higher
* mod_lua (with either Lua 5.1, 5.2 or LuaJIT)
* mod_status loaded (for enabling traffic statistics)

## Installing ##
First, install mod_lua (you can enable this during configure time with --enable-lua)

### Installing as a handler:
To install it as a handler, add the following to your httpd.conf in the appropriate VirtualHost:

    LuaMapHandler ^/server-status$ /path/to/server-status.lua
    
### Installing as a web app:
To install as a plain web-app, enable .lua scripts to be handled by mod_lua, by adding the following 
to your appropriate VirtualHost configuration:

    AddHandler lua-script .lua

Then just put the `.lua` script somewhere in your document root and visit the page.
