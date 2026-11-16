/*
 * Browser WebSocket module for LÖVR's Emscripten build.
 *
 * The browser owns the actual WebSocket.  This module exposes a small,
 * nonblocking event queue to Lua:
 *
 *   local ws = require("lovr_websocket")
 *   ws.open("wss://...")
 *   ws.send("...")
 *   local event = ws.poll()  -- nil | {type="open"|"message"|"close"|"error", ...}
 *   ws.close()
 *
 * Build instructions are in web/README.md.
 */
#include <emscripten/websocket.h>
#include <lua.h>
#include <lauxlib.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

#define WS_MAX_EVENTS 256
#define WS_MAX_MESSAGE (1024 * 1024)

typedef struct {
  int type;
  char* data;
  size_t length;
  uint16_t code;
  char* message;
} WsEvent;

enum {
  WS_EVENT_OPEN = 1,
  WS_EVENT_MESSAGE = 2,
  WS_EVENT_CLOSE = 3,
  WS_EVENT_ERROR = 4
};

static WsEvent events[WS_MAX_EVENTS];
static int event_head = 0;
static int event_tail = 0;
static int event_count = 0;
static int socket_handle = -1;

static void ws_push_event(int type, const void* data, size_t length,
    uint16_t code, const char* message) {
  if (event_count >= WS_MAX_EVENTS) return;
  WsEvent* event = &events[event_tail];
  memset(event, 0, sizeof(*event));
  event->type = type;
  event->code = code;
  if (data != NULL && length > 0) {
    event->length = length > WS_MAX_MESSAGE ? WS_MAX_MESSAGE : length;
    event->data = (char*) malloc(event->length);
    if (event->data != NULL) memcpy(event->data, data, event->length);
    else event->length = 0;
  }
  if (message != NULL) {
    size_t size = strlen(message);
    event->message = (char*) malloc(size + 1);
    if (event->message != NULL) memcpy(event->message, message, size + 1);
  }
  event_tail = (event_tail + 1) % WS_MAX_EVENTS;
  event_count++;
}

static void ws_clear_events(void) {
  while (event_count > 0) {
    WsEvent* event = &events[event_head];
    free(event->data);
    free(event->message);
    memset(event, 0, sizeof(*event));
    event_head = (event_head + 1) % WS_MAX_EVENTS;
    event_count--;
  }
}

static bool ws_on_open(int type, const EmscriptenWebSocketOpenEvent* event,
    void* user_data) {
  (void) type;
  (void) event;
  (void) user_data;
  ws_push_event(WS_EVENT_OPEN, NULL, 0, 0, NULL);
  return true;
}

static bool ws_on_message(int type,
    const EmscriptenWebSocketMessageEvent* event, void* user_data) {
  (void) type;
  (void) user_data;
  ws_push_event(WS_EVENT_MESSAGE, event->data, event->numBytes, 0, NULL);
  return true;
}

static bool ws_on_close(int type, const EmscriptenWebSocketCloseEvent* event,
    void* user_data) {
  (void) type;
  (void) user_data;
  ws_push_event(WS_EVENT_CLOSE, NULL, 0, event->code, event->reason);
  return true;
}

static bool ws_on_error(int type, const EmscriptenWebSocketErrorEvent* event,
    void* user_data) {
  (void) type;
  (void) event;
  (void) user_data;
  ws_push_event(WS_EVENT_ERROR, NULL, 0, 0, "websocket error");
  return true;
}

static int l_open(lua_State* L) {
  const char* url = luaL_checkstring(L, 1);
  if (socket_handle >= 0) {
    emscripten_websocket_close(socket_handle, 1000, "reconnect");
    emscripten_websocket_delete(socket_handle);
    socket_handle = -1;
  }
  ws_clear_events();
  EmscriptenWebSocketCreateAttributes attributes;
  attributes.url = url;
  attributes.protocols = NULL;
  attributes.createOnMainThread = true;
  socket_handle = emscripten_websocket_new(&attributes);
  if (socket_handle <= 0) {
    socket_handle = -1;
    lua_pushboolean(L, 0);
    lua_pushstring(L, "could not create WebSocket");
    return 2;
  }
  emscripten_websocket_set_onopen_callback(socket_handle, NULL, ws_on_open);
  emscripten_websocket_set_onmessage_callback(socket_handle, NULL,
    ws_on_message);
  emscripten_websocket_set_onclose_callback(socket_handle, NULL, ws_on_close);
  emscripten_websocket_set_onerror_callback(socket_handle, NULL, ws_on_error);
  lua_pushboolean(L, 1);
  return 1;
}

static int l_send(lua_State* L) {
  size_t length = 0;
  const char* data = luaL_checklstring(L, 1, &length);
  if (socket_handle < 0) {
    lua_pushboolean(L, 0);
    lua_pushstring(L, "websocket is not open");
    return 2;
  }
  EMSCRIPTEN_RESULT result = emscripten_websocket_send_utf8_text(
    socket_handle, data);
  if (result != EMSCRIPTEN_RESULT_SUCCESS) {
    lua_pushboolean(L, 0);
    lua_pushstring(L, "websocket send failed");
    return 2;
  }
  lua_pushboolean(L, 1);
  return 1;
}

static int l_poll(lua_State* L) {
  if (event_count == 0) {
    lua_pushnil(L);
    return 1;
  }
  WsEvent* event = &events[event_head];
  lua_newtable(L);
  if (event->type == WS_EVENT_OPEN) {
    lua_pushstring(L, "open");
    lua_setfield(L, -2, "type");
  } else if (event->type == WS_EVENT_MESSAGE) {
    lua_pushstring(L, "message");
    lua_setfield(L, -2, "type");
    lua_pushlstring(L, event->data, event->length);
    lua_setfield(L, -2, "data");
  } else if (event->type == WS_EVENT_CLOSE) {
    lua_pushstring(L, "close");
    lua_setfield(L, -2, "type");
    lua_pushinteger(L, event->code);
    lua_setfield(L, -2, "code");
    if (event->message != NULL) {
      lua_pushstring(L, event->message);
      lua_setfield(L, -2, "message");
    }
  } else {
    lua_pushstring(L, "error");
    lua_setfield(L, -2, "type");
    if (event->message != NULL) {
      lua_pushstring(L, event->message);
      lua_setfield(L, -2, "message");
    }
  }
  free(event->data);
  free(event->message);
  memset(event, 0, sizeof(*event));
  event_head = (event_head + 1) % WS_MAX_EVENTS;
  event_count--;
  return 1;
}

static int l_close(lua_State* L) {
  if (socket_handle >= 0) {
    emscripten_websocket_close(socket_handle, 1000, "client close");
    emscripten_websocket_delete(socket_handle);
    socket_handle = -1;
  }
  ws_clear_events();
  lua_pushboolean(L, 1);
  return 1;
}

static int l_state(lua_State* L) {
  unsigned short state = 3;
  if (socket_handle >= 0) {
    emscripten_websocket_get_ready_state(socket_handle, &state);
  }
  lua_pushinteger(L, state);
  return 1;
}

static const luaL_Reg functions[] = {
  { "open", l_open },
  { "send", l_send },
  { "poll", l_poll },
  { "close", l_close },
  { "state", l_state },
  { NULL, NULL }
};

int luaopen_lovr_websocket(lua_State* L) {
#if LUA_VERSION_NUM >= 502
  luaL_newlib(L, functions);
#else
  luaL_register(L, "lovr_websocket", functions);
#endif
  return 1;
}

void lovr_websocket_preload(lua_State* L) {
  lua_getglobal(L, "package");
  lua_getfield(L, -1, "preload");
  lua_pushcfunction(L, luaopen_lovr_websocket);
  lua_setfield(L, -2, "lovr_websocket");
  lua_pop(L, 2);
}
