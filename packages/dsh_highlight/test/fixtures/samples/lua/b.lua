local json = require("json")
local Class = {}
Class.__index = Class

function Class.new(name, ...)
  local self = setmetatable({}, Class)
  self.name, self.args = name, { ... }
  return self
end

function Class:greet(greeting)
  greeting = greeting or "hello"
  return string.format("%s, %s! #%d", greeting, self.name, #self.args)
end

local t <const> = { 10, 20; x = 1, ["y z"] = 2, [3] = 0x1F, [4.5] = 1e3 }
local long = [==[
long ]] string with "quotes"
]==]
--[==[ block
comment ]==]
for k, v in pairs(t) do
  if type(v) == "number" and v % 2 == 0 then print(k, v // 2, v ~ 1, v << 2) elseif not v then break else goto skip end
  ::skip::
end
repeat local n = (n or 0) + 1 until n >= 3
local s = 'esc \' \n \065 \x41 \u{48} \z
         continued' .. "tab\t" .. #t
local ok, err = pcall(function() error({ code = 1 }) end)
return setmetatable(Class, { __call = function(cls, ...) return cls.new(...) end })
