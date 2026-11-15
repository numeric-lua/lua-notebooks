--
-- Small LaTeX-to-Unicode renderer for inline markdown math.
-- This is not a TeX engine; it handles common symbols, superscripts,
-- subscripts, sqrt, and simple frac(a,b) forms.
--
local Math = {}

local SYMBOLS = {
  alpha = "alpha", beta = "beta", gamma = "gamma", delta = "delta", epsilon = "epsilon",
  theta = "theta", lambda = "lambda", mu = "mu", pi = "pi", rho = "rho",
  sigma = "sigma", tau = "tau", phi = "phi", omega = "omega", Gamma = "Gamma",
  Delta = "Delta", Theta = "Theta", Lambda = "Lambda", Pi = "Pi", Sigma = "Sigma",
  Phi = "Phi", Omega = "Omega", sum = "sum", prod = "prod", int = "int",
  infty = "inf", partial = "partial", nabla = "nabla", pm = "+/-", mp = "-/+",
  times = "x", cdot = ".", le = "<=", leq = "<=", ge = ">=",
  geq = ">=", ne = "!=", neq = "!=", to = "->", rightarrow = "->",
  approx = "~=", sqrt = "sqrt", quad = "  ", space = " ",
}

local SUPER = {
  ["0"]="⁰", ["1"]="¹", ["2"]="²", ["3"]="³", ["4"]="⁴",
  ["5"]="⁵", ["6"]="⁶", ["7"]="⁷", ["8"]="⁸", ["9"]="⁹",
  ["+"]="⁺", ["-"]="⁻", ["="]="⁼", ["("]="⁽", [")"]="⁾",
  n="ⁿ", i="ⁱ",
}
local SUB = {
  ["0"]="₀", ["1"]="₁", ["2"]="₂", ["3"]="₃", ["4"]="₄",
  ["5"]="₅", ["6"]="₆", ["7"]="₇", ["8"]="₈", ["9"]="₉",
  ["+"]="₊", ["-"]="₋", ["="]="₌", ["("]="₍", [")"]="₎",
  i="ᵢ", j="ⱼ", n="ₙ", x="ₓ",
}

local function script(value, map)
  local pieces = {}
  for index = 1, #value do
    local char = value:sub(index, index)
    local mapped = map[char]
    if mapped == nil then return nil end
    pieces[#pieces + 1] = mapped
  end
  return table.concat(pieces)
end

function Math.render(expression)
  local text = expression
  text = text:gsub("\\frac%s*{([^{}]*)}%s*{([^{}]*)}", "(%1)/(%2)")
  text = text:gsub("\\sqrt%s*{([^{}]*)}", "√(%1)")
  text = text:gsub("\\(%a+)", function(name) return SYMBOLS[name] or name end)
  text = text:gsub("([%w%)%]])%^(%b{})", function(base, value)
    local mapped = script(value:sub(2, -2), SUPER)
    return mapped and (base .. mapped) or (base .. "^" .. value)
  end)
  text = text:gsub("([%w%)%]])%^(%w+)", function(base, value)
    local mapped = script(value, SUPER)
    return mapped and (base .. mapped) or (base .. "^" .. value)
  end)
  text = text:gsub("([%w%)%]])_(%b{})", function(base, value)
    local mapped = script(value:sub(2, -2), SUB)
    return mapped and (base .. mapped) or (base .. "_" .. value)
  end)
  text = text:gsub("([%w%)%]])_(%w+)", function(base, value)
    local mapped = script(value, SUB)
    return mapped and (base .. mapped) or (base .. "_" .. value)
  end)
  text = text:gsub("[{}]", "")
  return text
end

function Math.inline(text)
  return (text:gsub("%$(.-)%$", function(expression)
    return Math.render(expression)
  end))
end

return Math
