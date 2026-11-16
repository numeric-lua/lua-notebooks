#ifndef LOVR_WEBSOCKET_H
#define LOVR_WEBSOCKET_H

#include <lua.h>

int luaopen_lovr_websocket(lua_State* L);

/* Register the module in package.preload before the project boot script runs. */
void lovr_websocket_preload(lua_State* L);

#endif
