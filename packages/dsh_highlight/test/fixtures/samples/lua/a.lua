-- Lua sample
local M = {}
local count = 0

--[[ multi-line
comment ]]
function M.add(a, b)
  return a + b
end

local function fib(n)
  if n < 2 then return n end
  return fib(n - 1) + fib(n - 2)
end

local t = { 1, 2, three = 3, ["four"] = 4.5e1, nested = { x = 0xFF } }
for i, v in ipairs(t) do
  print(i, v, "tab\t", 'single \'q\'', [[long
string]])
end

while count < 3 do
  count = count + 1
  if count == 2 and not nil then goto continue end
  ::continue::
end

setmetatable(M, { __index = function(_, k) return k .. "!" end })
return M
