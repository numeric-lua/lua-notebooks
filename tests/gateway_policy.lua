local Policy = require("notebook.gateway_policy")
local request = "GET /?token=abc HTTP/1.1\r\nOrigin: https://example.test\r\n\r\n"
assert(Policy.authorize(request, { token = "abc", origin = "https://example.test" }))
assert(not Policy.authorize(request, { token = "nope" }))
assert(not Policy.authorize(request, { origin = "https://evil.test" }))
assert(not Policy.authorize(request, { token = "abc", token_expires = 1,
  now = 2 }))
assert(not Policy.check_frame(100, 10))
print("gateway policy ok")
