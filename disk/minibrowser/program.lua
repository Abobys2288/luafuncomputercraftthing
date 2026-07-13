-- CCOS Program: Mini Browser
-- Lightweight HTML/CSS/JS browser for CCOS.
-- Supports: HTML4/5 parsing, CSS selectors (tag/class/id/descendant),
--   CSS shorthand (margin/padding/border), CSS specificity,
--   JS-to-Lua transpiler for simple scripts, HTTP/file/site fetch,
--   image loading, history, bookmarks.
-- Uses only system API; does not modify OS code.

local D = _G._desktop
local API = _G.ccos_api
local R = API and API.getRenderer and API.getRenderer() or _G.ccos_render
local K = {BLACK=0, WHITE=1, GRAY=2, LGRAY=3, DGRAY=4, DBLUE=19, RED=11, GREEN=9, BLUE=5}

-- ============================================================
-- UTILITIES
-- ============================================================
local function clip(text, w)
    if API and API.clipText then return API.clipText(text, w) end
    if R.clipText then return R.clipText(text, w) end
    return tostring(text or "")
end

local function drawText(x, y, text, fg, bg, w)
    if w then text = clip(text, w) end
    if API and API.drawText then API.drawText(x, y, text, fg, bg)
    else R.drawText(x, y, text, fg, bg) end
end

local function textWidth(text)
    if R.textWidth then return R.textWidth(text) end
    return #tostring(text or "") * 6
end

local function button(x, y, w, text)
    if w <= 0 then return end
    if R.drawButtonText then R.drawButtonText(x, y, w, 14, text, false, K.BLACK, K.GRAY)
    else R.drawButton(x, y, w, 14, false); drawText(x + 4, y + 3, text, K.BLACK, K.GRAY, w - 8) end
end

local function splitLines(text)
    local lines = {}
    text = tostring(text or "")
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do table.insert(lines, line) end
    if #lines == 0 then lines = {""} end
    return lines
end

local function trim(s)
    return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function startsWith(s, prefix)
    return tostring(s or ""):sub(1, #prefix) == prefix
end

local function endsWith(s, suffix)
    return #s >= #suffix and s:sub(-#suffix) == suffix
end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

local function parseInt(s, default)
    local n = tonumber(tostring(s or ""):match("^-?%d+"))
    return n or (default or 0)
end

local function parseColor(s)
    s = trim(tostring(s or "")):lower()
    if s == "" then return nil end
    -- named colors
    local named = {
        black=0, white=1, gray=2, silver=3, darkgray=4, grey=4,
        blue=5, darkblue=6, cyan=7, lightblue=8, green=9, darkgreen=10,
        red=11, darkred=12, yellow=13, orange=14, brown=15, purple=16,
        pink=17, navy=27, maroon=12, teal=30, lime=9,
    }
    if named[s] then return named[s] end
    -- hex #rgb / #rrggbb
    if s:sub(1,1) == "#" then
        local hex = s:sub(2)
        if #hex == 3 then
            local r = tonumber(hex:sub(1,1)..hex:sub(1,1), 16) or 0
            local g = tonumber(hex:sub(2,2)..hex:sub(2,2), 16) or 0
            local b = tonumber(hex:sub(3,3)..hex:sub(3,3), 16) or 0
            return colorToPalette(r, g, b)
        elseif #hex == 6 then
            local r = tonumber(hex:sub(1,2), 16) or 0
            local g = tonumber(hex:sub(3,4), 16) or 0
            local b = tonumber(hex:sub(5,6), 16) or 0
            return colorToPalette(r, g, b)
        end
    end
    -- rgb(r,g,b)
    local r, g, b = s:match("rgb%s*%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*%)")
    if r then return colorToPalette(tonumber(r), tonumber(g), tonumber(b)) end
    return nil
end

-- Map RGB to nearest CCOS 256-color palette index.
function colorToPalette(r, g, b)
    r, g, b = math.floor(r or 0), math.floor(g or 0), math.floor(b or 0)
    -- W95 range 0-31 first (simplified: only exact named lookups are handled elsewhere)
    -- 6x6x6 color cube 32-215
    local function nearest(v) return math.min(5, math.max(0, math.floor(v / 51 + 0.5))) end
    local ri, gi, bi = nearest(r), nearest(g), nearest(b)
    return 32 + ri * 36 + gi * 6 + bi
end

local function hasValue(t, v)
    for _, x in ipairs(t) do if x == v then return true end end
    return false
end

local function copyTable(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end


-- ============================================================
-- HTML TOKENIZER & PARSER
-- ============================================================
local VOID_TAGS = {br=true, hr=true, img=true, input=true, meta=true, link=true, base=true, area=true, col=true, embed=true, param=true, source=true, track=true, wbr=true}
local RAW_TEXT_TAGS = {script=true, style=true}
local AUTO_CLOSE_TAGS = {h1=true, h2=true, h3=true, h4=true, h5=true, h6=true, p=true, li=true, dt=true, dd=true, option=true, tr=true, td=true, th=true}
local BLOCK_TAGS = {html=true, body=true, head=true, div=true, p=true, h1=true, h2=true, h3=true, h4=true, h5=true, h6=true, ul=true, ol=true, li=true, table=true, tr=true, td=true, th=true, pre=true, form=true, hr=true, center=true}

local function htmlTokenize(html)
    local tokens = {}
    local i = 1
    local n = #html
    while i <= n do
        if html:sub(i, i+3) == "<!--" then
            local e = html:find("-->", i+4, true)
            if not e then break end
            i = e + 3
        elseif html:sub(i, i) == "<" then
            local e = html:find(">", i+1, true)
            if not e then break end
            local tagText = html:sub(i+1, e-1)
            i = e + 1
            local closing = tagText:sub(1,1) == "/"
            local selfClose = tagText:sub(-1,-1) == "/"
            if selfClose then tagText = tagText:sub(1, -2) end
            if closing then tagText = tagText:sub(2) end
            tagText = trim(tagText)
            -- Skip doctype and other <!...> declarations
            if tagText:sub(1, 1) == "!" then
                -- doctype or SGML declaration; ignore
            else
            local tagName = tagText:match("^[%w_:-]+") or ""
            tagName = tagName:lower()
            if tagName ~= "" then
            local attrs = {}
            local rest = tagText:sub(#tagName + 1)
            -- parse attributes
            while rest ~= "" do
                rest = trim(rest)
                if rest == "" then break end
                local name, val
                local eqPos = rest:find("=", 1, true)
                local spPos = rest:find(" ", 1, true)
                if eqPos and (not spPos or eqPos < spPos) then
                    name = trim(rest:sub(1, eqPos - 1)):lower()
                    rest = rest:sub(eqPos + 1)
                    rest = trim(rest)
                    local q = rest:sub(1,1)
                    if q == '"' or q == "'" then
                        local endp = rest:find(q, 2, true)
                        if endp then
                            val = rest:sub(2, endp - 1)
                            rest = rest:sub(endp + 1)
                        else
                            val = rest:sub(2)
                            rest = ""
                        end
                    else
                        local sp = rest:find(" ", 1, true)
                        if sp then
                            val = rest:sub(1, sp - 1)
                            rest = rest:sub(sp + 1)
                        else
                            val = rest
                            rest = ""
                        end
                    end
                else
                    if spPos then
                        name = trim(rest:sub(1, spPos - 1)):lower()
                        rest = rest:sub(spPos + 1)
                    else
                        name = trim(rest):lower()
                        rest = ""
                    end
                    val = ""
                end
                if name and name ~= "" then attrs[name] = val end
            end
            table.insert(tokens, {type="tag", name=tagName, attrs=attrs, closing=closing, selfClose=selfClose or VOID_TAGS[tagName]})
            end
            end
        else
            local e = html:find("<", i, true) or (n + 1)
            local text = html:sub(i, e - 1)
            -- decode entities
            text = text:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&nbsp;", " "):gsub("&#(%d+);", function(n) return string.char(tonumber(n) % 256) end):gsub("&#x(%x+);", function(n) return string.char(tonumber(n, 16) % 256) end)
            table.insert(tokens, {type="text", text=text})
            i = e
        end
    end
    return tokens
end

local function createElement(tag, attrs)
    return {
        type = "element",
        tag = tag,
        attrs = attrs or {},
        children = {},
        parent = nil,
        style = {},      -- computed style
        layout = nil,    -- layout box (computed later)
        id = nil,
        classes = {},
    }
end

local function createTextNode(text)
    return {type = "text", text = text or "", parent = nil}
end

function parseHTML(html)
    local tokens = htmlTokenize(html)
    local root = createElement("html", {})
    local stack = {root}
    local i = 1
    while i <= #tokens do
        local tok = tokens[i]
        if tok.type == "text" then
            if tok.text ~= "" then
                local parent = stack[#stack]
                local node = createTextNode(tok.text)
                node.parent = parent
                table.insert(parent.children, node)
            end
        elseif tok.type == "tag" then
            if tok.closing then
                -- pop until matching tag (including the matching tag itself)
                for j = #stack, 1, -1 do
                    if stack[j].tag == tok.name then
                        while #stack >= j do table.remove(stack) end
                        break
                    end
                end
            else
                -- Auto-close certain tags when a new block-level tag appears.
                if BLOCK_TAGS[tok.name] then
                    while #stack > 1 do
                        local top = stack[#stack]
                        if AUTO_CLOSE_TAGS[top.tag] then
                            table.remove(stack)
                        else
                            break
                        end
                    end
                end
                local parent = stack[#stack]
                local el = createElement(tok.name, copyTable(tok.attrs))
                el.parent = parent
                el.id = el.attrs.id
                for c in tostring(el.attrs.class or ""):gmatch("%S+") do table.insert(el.classes, c) end
                table.insert(parent.children, el)
                if not (tok.selfClose or VOID_TAGS[tok.name]) then
                    if RAW_TEXT_TAGS[tok.name] and i < #tokens then
                        i = i + 1
                        local rawTok = tokens[i]
                        if rawTok and rawTok.type == "text" then
                            local rawNode = createTextNode(rawTok.text)
                            rawNode.parent = el
                            table.insert(el.children, rawNode)
                        end
                    else
                        table.insert(stack, el)
                    end
                end
            end
        end
        i = i + 1
    end
    return root
end

-- If parser wrapped an explicit <html> inside the implicit root, lift it.
local function normalizeRoot(root)
    if root.tag == "html" and #root.children == 1 then
        local child = root.children[1]
        if child.type == "element" and child.tag == "html" then
            return child
        end
    end
    return root
end

local function getElementById(root, id)
    if root.id == id then return root end
    for _, child in ipairs(root.children or {}) do
        if child.type == "element" then
            local found = getElementById(child, id)
            if found then return found end
        end
    end
    return nil
end

local function getElementsByTag(root, tag, out)
    out = out or {}
    if root.tag == tag then table.insert(out, root) end
    for _, child in ipairs(root.children or {}) do
        if child.type == "element" then getElementsByTag(child, tag, out) end
    end
    return out
end


-- ============================================================
-- CSS PARSER & COMPUTED STYLES
-- ============================================================
local DEFAULT_STYLES = {
    html   = {display="block"},
    head   = {display="none"},
    meta   = {display="none"},
    link   = {display="none"},
    script = {display="none"},
    style  = {display="none"},
    body   = {display="block", color=0, background_color=nil},
    nav    = {display="block"},
    header = {display="block"},
    footer = {display="block"},
    section= {display="block"},
    article= {display="block"},
    aside  = {display="block"},
    main   = {display="block"},
    div    = {display="block"},
    p      = {display="block", margin_top=8, margin_bottom=8},
    h1     = {display="block", font_size=16, font_weight="bold", margin_top=12, margin_bottom=8},
    h2     = {display="block", font_size=14, font_weight="bold", margin_top=10, margin_bottom=6},
    h3     = {display="block", font_size=12, font_weight="bold", margin_top=8, margin_bottom=4},
    h4     = {display="block", font_size=10, font_weight="bold"},
    h5     = {display="block", font_size=9, font_weight="bold"},
    h6     = {display="block", font_size=8, font_weight="bold"},
    span   = {display="inline"},
    a      = {display="inline", color=5, text_decoration="underline"},
    b      = {display="inline", font_weight="bold"},
    strong = {display="inline", font_weight="bold"},
    i      = {display="inline", font_style="italic"},
    em     = {display="inline", font_style="italic"},
    u      = {display="inline", text_decoration="underline"},
    s      = {display="inline", text_decoration="line-through"},
    br     = {display="inline"},
    hr     = {display="block", border_top=1, margin_top=6, margin_bottom=6, color=4},
    button = {display="inline-block", color=0, background_color=3, border=1, padding_left=4, padding_right=4, padding_top=2, padding_bottom=2},
    input  = {display="inline-block", color=0, background_color=1, border=1, padding_left=2, padding_right=2, padding_top=1, padding_bottom=1},
    img    = {display="inline-block"},
    pre    = {display="block", font_family="mono", white_space="pre", background_color=22},
    code   = {display="inline", font_family="mono", background_color=22},
    ul     = {display="block", margin_top=4, margin_bottom=4, padding_left=16},
    ol     = {display="block", margin_top=4, margin_bottom=4, padding_left=16},
    li     = {display="list-item"},
    table  = {display="block", border=1, margin_top=4, margin_bottom=4},
    tr     = {display="block"},
    td     = {display="inline-block", border=1, padding_left=2, padding_right=2, padding_top=1, padding_bottom=1},
    th     = {display="inline-block", border=1, font_weight="bold", padding_left=2, padding_right=2, padding_top=1, padding_bottom=1},
    label  = {display="inline"},
    form   = {display="block"},
    center = {display="block", text_align="center"},
}

local function parseStyleValue(prop, value)
    value = trim(tostring(value or "")):lower()
    if value == "" then return nil end
    if prop == "display" then
        if value == "none" or value == "block" or value == "inline" or value == "inline-block" or value == "list-item" then return value end
        return "block"
    elseif prop == "color" or prop == "background_color" or prop == "border_color" then
        return parseColor(value)
    elseif prop == "font_size" then
        return parseInt(value, 8)
    elseif prop == "font_weight" then
        if value == "bold" or tonumber(value) >= 600 then return "bold" end
        return "normal"
    elseif prop == "font_style" then
        return value == "italic" and "italic" or "normal"
    elseif prop == "text_align" then
        if value == "left" or value == "center" or value == "right" then return value end
        return "left"
    elseif prop == "text_decoration" then
        if value == "underline" or value == "line-through" or value == "none" then return value end
        return "none"
    elseif prop == "white_space" then
        return value == "pre" and "pre" or "normal"
    elseif prop == "width" or prop == "height" then
        if value:find("%%") then return {type="percent", value=parseInt(value, 0)}
        else return {type="px", value=parseInt(value, 0)} end
    elseif prop == "margin" or prop == "padding" then
        return parseInt(value, 0)
    elseif prop == "margin_top" or prop == "margin_bottom" or prop == "margin_left" or prop == "margin_right" then
        return parseInt(value, 0)
    elseif prop == "padding_top" or prop == "padding_bottom" or prop == "padding_left" or prop == "padding_right" then
        return parseInt(value, 0)
    elseif prop == "border" then
        -- accept "1px solid #color" or just "1"
        local w = tonumber(value:match("^(%d+)")) or 1
        return w
    elseif prop == "border_top" or prop == "border_bottom" or prop == "border_left" or prop == "border_right" then
        return tonumber(value) or parseInt(value, 1)
    end
    return nil
end

local function parseInlineStyle(styleStr)
    local style = {}
    if not styleStr then return style end
    for decl in styleStr:gmatch("([^;]+)") do
        decl = trim(decl)
        local eq = decl:find(":", 1, true)
        if eq then
            local prop = trim(decl:sub(1, eq - 1)):lower():gsub("%-", "_")
            local val = trim(decl:sub(eq + 1))
            if prop == "margin" or prop == "padding" then
                local parts = {}
                for v in val:gmatch("(%d+)") do table.insert(parts, tonumber(v)) end
                local top, right, bottom, left
                if #parts >= 4 then top, right, bottom, left = parts[1], parts[2], parts[3], parts[4]
                elseif #parts == 3 then top, right, bottom, left = parts[1], parts[2], parts[3], parts[2]
                elseif #parts == 2 then top, right, bottom, left = parts[1], parts[2], parts[1], parts[2]
                elseif #parts == 1 then top, right, bottom, left = parts[1], parts[1], parts[1], parts[1]
                else top, right, bottom, left = 0, 0, 0, 0 end
                style[prop .. "_top"] = top
                style[prop .. "_right"] = right
                style[prop .. "_bottom"] = bottom
                style[prop .. "_left"] = left
                style[prop] = top
            elseif prop == "border" then
                local w = tonumber(val:match("^(%d+)")) or 1
                style["border"] = w
                style["border_top"] = w
                style["border_bottom"] = w
                style["border_left"] = w
                style["border_right"] = w
                local color = val:match("#(%x+)")
                if color then style["border_color"] = parseColor("#" .. color) end
            else
                style[prop] = parseStyleValue(prop, val)
            end
        end
    end
    return style
end

local function parseCSS(cssText)
    local rules = {}
    cssText = tostring(cssText or "")
    cssText = cssText:gsub("/%*.-%*/", "")
    local i = 1
    while i <= #cssText do
        local open = cssText:find("{", i, true)
        if not open then break end
        local close = cssText:find("}", open, true)
        if not close then break end
        local selectorsStr = trim(cssText:sub(i, open - 1))
        local body = trim(cssText:sub(open + 1, close - 1))
        local decls = parseInlineStyle(body)
        for selector in selectorsStr:gmatch("[^,]+") do
            selector = trim(selector)
            if selector ~= "" then
                table.insert(rules, {selector=selector, style=decls})
            end
        end
        i = close + 1
    end
    return rules
end

local function parseSelector(sel)
    local parts = {}
    for part in sel:gmatch("[^,]+") do
        part = trim(part)
        if part ~= "" then
            local p = {tag=nil, id=nil, classes={}, universal=false, child=false}
            if part == "*" then p.universal = true
            else
                local remaining = part
                local tag = remaining:match("^([%w_%-]+)")
                if tag then p.tag = tag:lower(); remaining = remaining:sub(#tag + 1) end
                for cls in remaining:gmatch("%.([%w_%-]+)") do table.insert(p.classes, cls) end
                local id = remaining:match("#([%w_%-]+)")
                if id then p.id = id end
            end
            table.insert(parts, p)
        end
    end
    return parts
end

local function matchesPart(el, part)
    if not el or el.type ~= "element" then return false end
    if part.universal then return true end
    if part.tag and el.tag ~= part.tag then return false end
    if part.id and el.id ~= part.id then return false end
    for _, cls in ipairs(part.classes) do
        local found = false
        for _, c in ipairs(el.classes) do if c == cls then found = true; break end end
        if not found then return false end
    end
    return true
end

local function selectorMatchesRule(ruleParts, el)
    if #ruleParts == 0 then return false end
    if not matchesPart(el, ruleParts[#ruleParts]) then return false end
    if #ruleParts == 1 then return true end
    local current = el.parent
    local pi = #ruleParts - 1
    while pi >= 1 and current do
        if matchesPart(current, ruleParts[pi]) then pi = pi - 1 end
        current = current.parent
    end
    return pi == 0
end

local function specificity(parts)
    local a, b, c = 0, 0, 0
    for _, part in ipairs(parts) do
        if part.id then a = a + 1 end
        b = b + #part.classes
        if part.tag and not part.universal then c = c + 1 end
    end
    return a * 100 + b * 10 + c
end

local function computeStyles(root, cssRules)
    local parsedRules = {}
    for _, rule in ipairs(cssRules or {}) do
        local parts = parseSelector(rule.selector)
        if #parts > 0 then
            table.insert(parsedRules, {parts=parts, style=rule.style, spec=specificity(parts)})
        end
    end
    table.sort(parsedRules, function(a, b) return a.spec < b.spec end)

    local function walk(el)
        if el.type ~= "element" then return end
        local style = {}
        local def = DEFAULT_STYLES[el.tag] or {display="inline"}
        for k, v in pairs(def) do style[k] = v end
        for _, rule in ipairs(parsedRules) do
            if selectorMatchesRule(rule.parts, el) then
                for k, v in pairs(rule.style) do
                    if v ~= nil then style[k] = v end
                end
            end
        end
        local inline = parseInlineStyle(el.attrs.style)
        for k, v in pairs(inline) do
            if v ~= nil then style[k] = v end
        end
        el.style = style
        for _, child in ipairs(el.children) do walk(child) end
    end
    walk(root)
end


-- ============================================================
-- LAYOUT ENGINE
-- ============================================================
local LINE_HEIGHT = 8  -- 5x7 font + 1 px spacing

local function isBlockDisplay(display)
    return display == "block" or display == "list-item"
end

local function resolveDim(value, avail)
    if type(value) == "table" then
        if value.type == "px" then return value.value
        elseif value.type == "percent" then return math.floor(avail * value.value / 100) end
    end
    return 0
end

local function getNum(style, key, default)
    local v = style[key]
    if type(v) == "number" then return v end
    return default or 0
end

local function measureText(text)
    return textWidth(text)
end

-- Flatten an element's visible text into a single string (for buttons etc).
local function flattenText(el)
    if el.type == "text" then return el.text end
    local t = ""
    for _, c in ipairs(el.children or {}) do
        local s = flattenText(c)
        t = t .. s
    end
    return t
end

-- Collect inline items (words and inline elements) for a block container.
-- Items get their layout calculated and are returned as a flat list.
local function collectInlineItems(el, availW)
    local items = {}
    local function walk(node)
        if node.type == "text" then
            local text = node.text or ""
            local parent = node.parent
            local pre = parent and parent.style and parent.style.white_space == "pre"
            if pre then
                table.insert(items, {type="text", node=node, text=text, w=measureText(text), h=LINE_HEIGHT})
            else
                text = text:gsub("%s+", " ")
                if text ~= "" and text ~= " " then
                    for word, sp in text:gmatch("(%S+)(%s*)") do
                        local w = word .. sp
                        table.insert(items, {type="text", node=node, text=w, w=measureText(w), h=LINE_HEIGHT})
                    end
                end
            end
        elseif node.type == "element" then
            local display = (node.style or {}).display or "inline"
            if display == "none" then
                -- skip
            elseif display == "block" or display == "list-item" then
                table.insert(items, {type="block", node=node})
            else
                -- inline / inline-block: ensure layout exists
                if not node.layout then
                    layoutElement(node, {availW=availW})
                end
                table.insert(items, {type="element", node=node, w=node.layout.w, h=node.layout.h})
                if node.tag == "br" then
                    items[#items].forceBreak = true
                end
            end
        end
    end
    for _, child in ipairs(el.children or {}) do walk(child) end
    return items
end

-- Apply offset to convert relative child coordinates to absolute.
local function applyGlobalOffset(el, dx, dy)
    if not el or not el.layout then return end
    el.layout.x = (el.layout.x or 0) + dx
    el.layout.y = (el.layout.y or 0) + dy
    if el.type == "element" then
        for _, child in ipairs(el.children) do applyGlobalOffset(child, dx, dy) end
    end
end

-- Main layout function.
function layoutElement(el, ctx)
    if el.type == "text" then
        el.layout = {x=0, y=0, w=0, h=LINE_HEIGHT, display="inline"}
        return
    end

    local style = el.style or {}
    local display = style.display or "inline"
    if display == "none" then
        el.layout = {x=0, y=0, w=0, h=0, display="none"}
        return
    end

    local layout = {
        x = 0, y = 0,
        w = ctx.availW,
        h = 0,
        display = display,
        marginTop = getNum(style, "margin_top", 0) + getNum(style, "margin", 0),
        marginBottom = getNum(style, "margin_bottom", 0) + getNum(style, "margin", 0),
        marginLeft = getNum(style, "margin_left", 0) + getNum(style, "margin", 0),
        marginRight = getNum(style, "margin_right", 0) + getNum(style, "margin", 0),
        paddingTop = getNum(style, "padding_top", 0) + getNum(style, "padding", 0),
        paddingBottom = getNum(style, "padding_bottom", 0) + getNum(style, "padding", 0),
        paddingLeft = getNum(style, "padding_left", 0) + getNum(style, "padding", 0),
        paddingRight = getNum(style, "padding_right", 0) + getNum(style, "padding", 0),
        border = getNum(style, "border", 0),
        bg = style.background_color,
        fg = style.color,
        fontSize = getNum(style, "font_size", 8),
        textAlign = style.text_align or "left",
        clickable = el.tag == "a" or el.tag == "button" or el.tag == "input" or el.attrs.onclick,
    }

    if style.width then layout.w = resolveDim(style.width, ctx.availW) end
    local contentW = layout.w - layout.paddingLeft - layout.paddingRight - layout.border * 2
    if contentW < 1 then contentW = 1 end
    layout.contentW = contentW

    if isBlockDisplay(display) then
        -- Block layout: children stacked vertically, inline children flow in lines.
        local childY = layout.paddingTop + layout.border
        local maxContentW = 0
        local items = collectInlineItems(el, contentW)
        local lineItems = {}
        local lineW = 0
        local lineH = 0

        local function flushLine()
            if #lineItems == 0 then return end
            local totalW = 0
            for _, it in ipairs(lineItems) do totalW = totalW + it.w end
            local lineX = layout.paddingLeft + layout.border
            if layout.textAlign == "center" then lineX = lineX + math.max(0, math.floor((contentW - totalW) / 2))
            elseif layout.textAlign == "right" then lineX = lineX + math.max(0, contentW - totalW) end
            for _, it in ipairs(lineItems) do
                if it.type == "element" then
                    -- element already has relative layout inside its own box; position it absolutely
                    applyGlobalOffset(it.node, lineX, childY)
                elseif it.type == "text" then
                    it.lineX = lineX
                    it.lineY = childY
                end
                lineX = lineX + it.w
            end
            if totalW > maxContentW then maxContentW = totalW end
            childY = childY + lineH
            lineItems = {}
            lineW = 0
            lineH = 0
        end

        for _, it in ipairs(items) do
            if it.type == "block" then
                flushLine()
                local child = it.node
                layoutElement(child, {availW=contentW})
                child.layout.x = layout.paddingLeft + layout.border
                child.layout.y = childY + child.layout.marginTop
                applyGlobalOffset(child, 0, 0) -- already absolute after this
                childY = childY + child.layout.marginTop + child.layout.h + child.layout.marginBottom
                if child.layout.w > maxContentW then maxContentW = child.layout.w end
            else
                if it.w > contentW then it.w = contentW end
                if lineW + it.w > contentW and lineW > 0 then
                    flushLine()
                end
                table.insert(lineItems, it)
                lineW = lineW + it.w
                if it.h > lineH then lineH = it.h end
                if it.forceBreak then flushLine() end
            end
        end
        flushLine()
        el._inlineItems = items

        layout.contentH = math.max(0, childY - (layout.paddingTop + layout.border))
        if style.height then
            layout.h = resolveDim(style.height, ctx.availH or contentW)
        else
            layout.h = layout.contentH + layout.paddingTop + layout.paddingBottom + layout.border * 2
        end
    else
        -- Inline / inline-block layout
        if el.tag == "button" or el.tag == "input" then
            local txt = el.attrs.value or el.attrs.placeholder or flattenText(el)
            if txt == "" then txt = " " end
            local tw = measureText(txt)
            layout.w = tw + layout.paddingLeft + layout.paddingRight + layout.border * 2
            layout.h = LINE_HEIGHT + layout.paddingTop + layout.paddingBottom + layout.border * 2
            if layout.h < 14 then layout.h = 14 end
            if el.tag == "input" and el.attrs.type == "text" then
                layout.w = math.max(layout.w, 80)
            end
            layout.contentW = layout.w - layout.paddingLeft - layout.paddingRight - layout.border * 2
        elseif el.tag == "img" then
            layout.w = resolveDim(style.width, ctx.availW)
            layout.h = resolveDim(style.height, 9999)
            if layout.w == 0 then layout.w = 32 end
            if layout.h == 0 then layout.h = 32 end
            layout.contentW = layout.w
            layout.w = layout.w + layout.paddingLeft + layout.paddingRight + layout.border * 2
            layout.h = layout.h + layout.paddingTop + layout.paddingBottom + layout.border * 2
        elseif el.tag == "br" then
            layout.w = 0
            layout.h = LINE_HEIGHT
        elseif el.tag == "hr" then
            layout.w = ctx.availW
            layout.h = getNum(style, "border_top", 1) + getNum(style, "margin_top", 0) + getNum(style, "margin_bottom", 0)
        else
            -- inline container: span, a, b, i, etc.
            local childX = layout.paddingLeft + layout.border
            local childY = layout.paddingTop + layout.border
            local maxH = 0
            local inlineItems = {}
            local items = collectInlineItems(el, contentW)
            for _, it in ipairs(items) do
                if it.type == "block" then
                    -- block inside inline is treated as inline-block for simplicity
                    if not it.node.layout then layoutElement(it.node, {availW=contentW}) end
                    it.w = it.node.layout.w
                    it.h = it.node.layout.h
                end
                if it.type == "element" or it.type == "block" then
                    applyGlobalOffset(it.node, childX, childY)
                elseif it.type == "text" then
                    it.lineX = childX
                    it.lineY = childY
                end
                childX = childX + (it.w or 0)
                if (it.h or 0) > maxH then maxH = it.h end
                table.insert(inlineItems, it)
            end
            el._inlineItems = inlineItems
            layout.w = math.max(1, childX - (layout.paddingLeft + layout.border) + layout.paddingRight + layout.border)
            layout.h = math.max(LINE_HEIGHT, maxH) + layout.paddingTop + layout.paddingBottom + layout.border * 2
            layout.contentW = layout.w - layout.paddingLeft - layout.paddingRight - layout.border * 2
        end
    end

    el.layout = layout
end

local function getAbsoluteBounds(el)
    if not el.layout then return nil end
    local l = el.layout
    return {
        x = l.x, y = l.y,
        w = l.w, h = l.h,
        contentX = l.x + l.paddingLeft + l.border,
        contentY = l.y + l.paddingTop + l.border,
        contentW = l.contentW,
        contentH = l.h - l.paddingTop - l.paddingBottom - l.border * 2,
    }
end

-- ============================================================
-- RENDERER
-- ============================================================
local function drawBackground(x, y, w, h, color)
    if color ~= nil and w > 0 and h > 0 then
        R.fillRect(x, y, w, h, color)
    end
end

local function drawBorder(x, y, w, h, bw, color)
    if bw and bw > 0 and color then
        R.drawRect(x, y, w, h, color)
    end
end

local function drawTextLine(x, y, text, fg, bg, style)
    if not text or text == "" then return end
    if style and style.text_decoration == "underline" then
        local w = measureText(text)
        R.drawLine(x, y + LINE_HEIGHT - 1, x + w - 1, y + LINE_HEIGHT - 1, fg or K.BLACK)
    elseif style and style.text_decoration == "line-through" then
        local w = measureText(text)
        R.drawLine(x, y + math.floor(LINE_HEIGHT / 2), x + w - 1, y + math.floor(LINE_HEIGHT / 2), fg or K.BLACK)
    end
    drawText(x, y, text, fg, bg)
end

local function renderElement(el, scrollX, scrollY, clipRect)
    if el.type == "text" then return end
    if not el.layout then return end
    local l = el.layout
    if l.display == "none" then return end

    local x = l.x - scrollX
    local y = l.y - scrollY
    -- simple clip: skip if outside content area
    if clipRect then
        if x + l.w < clipRect.x or x > clipRect.x + clipRect.w or y + l.h < clipRect.y or y > clipRect.y + clipRect.h then return end
    end

    -- draw block background and border
    if isBlockDisplay(l.display) then
        drawBackground(x, y, l.w, l.h, l.bg)
        drawBorder(x, y, l.w, l.h, l.border, (el.style or {}).border_color or K.DGRAY)
        -- render inline children using pre-computed layout items
        for _, it in ipairs(el._inlineItems or {}) do
            if it.type == "element" then
                renderElement(it.node, scrollX, scrollY, clipRect)
            elseif it.type == "text" then
                local tx = x + it.lineX
                local ty = y + it.lineY
                if ty + it.h >= clipRect.y and ty <= clipRect.y + clipRect.h then
                    local fg = (el.style or {}).color or K.BLACK
                    local bg = l.bg
                    drawTextLine(tx, ty, it.text, fg, bg, el.style)
                end
            elseif it.type == "block" then
                renderElement(it.node, scrollX, scrollY, clipRect)
            end
        end
    else
        -- inline / inline-block element
        drawBackground(x, y, l.w, l.h, l.bg)
        drawBorder(x, y, l.w, l.h, l.border, (el.style or {}).border_color or K.DGRAY)
        if el.tag == "button" then
            if R.drawButtonText then
                R.drawButtonText(x, y, l.w, l.h, flattenText(el), false, l.fg or K.BLACK, l.bg or K.GRAY)
            else
                drawText(x + l.paddingLeft + l.border, y + l.paddingTop + l.border, flattenText(el), l.fg or K.BLACK, l.bg)
            end
        elseif el.tag == "input" then
            R.drawW95Sunken(x + l.border, y + l.border, l.w - l.border * 2, l.h - l.border * 2)
            local val = el.attrs.value or el.attrs.placeholder or ""
            local fg = el.attrs.value and (l.fg or K.BLACK) or K.DGRAY
            drawText(x + l.paddingLeft + l.border, y + l.paddingTop + l.border, val, fg, nil, l.contentW)
        elseif el.tag == "img" then
            local img = el._loadedImage
            if img then
                local drawW = math.min(img.w, l.w - l.paddingLeft - l.paddingRight - l.border * 2)
                local drawH = math.min(img.h, l.h - l.paddingTop - l.paddingBottom - l.border * 2)
                local ix = x + l.paddingLeft + l.border
                local iy = y + l.paddingTop + l.border
                for py = 1, drawH do
                    local row = img.pixels[py]
                    if row then
                        for px = 1, drawW do
                            local col = row[px]
                            if col and col ~= 254 then R.setPixel(ix + px - 1, iy + py - 1, col) end
                        end
                    end
                end
            else
                drawText(x + 2, y + 2, "[img]", K.DGRAY, l.bg)
            end
        elseif el.tag == "hr" then
            local bx = x + l.border
            local by = y + math.floor(l.h / 2)
            R.drawLine(bx, by, bx + l.w - l.border * 2, by, (el.style or {}).color or K.DGRAY)
        else
            -- span, a, b, i, etc.
            for _, it in ipairs(el._inlineItems or {}) do
                if it.type == "element" then
                    renderElement(it.node, scrollX, scrollY, clipRect)
                elseif it.type == "text" then
                    local tx = x + it.lineX
                    local ty = y + it.lineY
                    if not clipRect or (ty + it.h >= clipRect.y and ty <= clipRect.y + clipRect.h) then
                        drawTextLine(tx, ty, it.text, l.fg or K.BLACK, l.bg, el.style)
                    end
                elseif it.type == "block" then
                    renderElement(it.node, scrollX, scrollY, clipRect)
                end
            end
        end
    end
end

-- Find clickable element at screen coordinates (relative to content).
local function hitTest(el, mx, my, scrollX, scrollY)
    if el.type == "text" then return nil end
    if not el.layout then return nil end
    local l = el.layout
    if l.display == "none" then return nil end
    local x = l.x - scrollX
    local y = l.y - scrollY
    if mx >= x and mx < x + l.w and my >= y and my < y + l.h then
        -- check children first (for inline elements)
        if not isBlockDisplay(l.display) then
            for _, child in ipairs(el.children) do
                local hit = hitTest(child, mx, my, scrollX, scrollY)
                if hit then return hit end
            end
        else
            local items = collectInlineItems(el, l.contentW)
            for _, it in ipairs(items) do
                if it.type == "element" then
                    local hit = hitTest(it.node, mx, my, scrollX, scrollY)
                    if hit then return hit end
                end
            end
        end
        if l.clickable or el.attrs.onclick or el.tag == "a" or el.tag == "button" or el.tag == "input" then
            return el
        end
    end
    return nil
end


-- ============================================================
-- JS-LIKE RUNTIME (SANDBOXED LUA DSL)
-- ============================================================
local BrowserState = nil  -- set by main app

local function makeElementWrapper(el, app)
    if not el then return nil end
    if el._wrapper then return el._wrapper end
    local w = {}
    el._wrapper = w
    w._el = el

    w.getAttribute = function(_, name) return el.attrs[name] end
    w.setAttribute = function(_, name, value)
        el.attrs[name] = tostring(value)
        app.invalidateLayout()
    end

    local mt = {
        __index = function(_, key)
            if key == "innerText" then return flattenText(el) end
            if key == "value" then return el.attrs.value or "" end
            if key == "tagName" then return el.tag:upper() end
            if key == "id" then return el.id end
            if key == "onclick" then return el._onclick end
            if key == "onchange" then return el._onchange end
            if key == "style" then
                if not el._styleWrapper then
                    el._styleWrapper = {}
                    setmetatable(el._styleWrapper, {
                        __index = function(_, k) return (el.style or {})[k] end,
                        __newindex = function(_, k, v)
                            el.style = el.style or {}
                            el.style[k] = parseStyleValue(k, v)
                            app.invalidateLayout()
                        end
                    })
                end
                return el._styleWrapper
            end
            return nil
        end,
        __newindex = function(_, key, value)
            if key == "innerText" then
                el.children = {createTextNode(tostring(value))}
                el.children[1].parent = el
                app.invalidateLayout()
            elseif key == "value" then
                el.attrs.value = tostring(value)
                app.invalidateLayout()
            elseif key == "onclick" then
                el._onclick = value
            elseif key == "onchange" then
                el._onchange = value
            end
        end
    }
    setmetatable(w, mt)
    return w
end

local function makeDocument(app)
    local doc = {}
    doc.getElementById = function(_, id)
        local el = getElementById(app.domRoot, id)
        return makeElementWrapper(el, app)
    end
    doc.getElementsByTagName = function(_, tag)
        local list = getElementsByTag(app.domRoot, tag)
        local wrappers = {}
        for _, el in ipairs(list) do table.insert(wrappers, makeElementWrapper(el, app)) end
        return wrappers
    end
    return doc
end

local function makeConsole(app)
    return {
        log = function(_, ...)
            local parts = {}
            for i = 1, select("#", ...) do table.insert(parts, tostring(select(i, ...))) end
            app.setStatus("JS: " .. table.concat(parts, " "))
        end
    }
end

-- Basic JS-to-Lua transpiler for simple scripts
local function transpileJS(js)
    local s = js
    -- Strip comments
    s = s:gsub("/%*.-%*/", "")
    s = s:gsub("//[^\n]*", "")
    -- Operators
    s = s:gsub("===", "="):gsub("!==", "~="):gsub("!=", "~=")
    s = s:gsub("&&", " and "):gsub("||", " or ")
    s = s:gsub("%f[%w_]typeof%s+", "type("):gsub("%f[%w_]new%s+", "")
    -- Keywords
    s = s:gsub("%f[%w_]var%f[^%w_]", "local")
    s = s:gsub("%f[%w_]let%f[^%w_]", "local")
    s = s:gsub("%f[%w_]const%f[^%w_]", "local")
    s = s:gsub("%f[%w_]null%f[^%w_]", "nil")
    s = s:gsub("%f[%w_]undefined%f[^%w_]", "nil")
    -- Remove semicolons
    s = s:gsub(";", "")
    -- function name() { → function name()
    s = s:gsub("function%s+(%w+)%s*%(([^)]*)%)%s*{", "function %1(%2)")
    s = s:gsub("function%s*%(([^)]*)%)%s*{", "function(%1)")
    -- if (cond) { → if cond then
    s = s:gsub("if%s*%(([^)]+)%)%s*{", "if %1 then")
    -- } else if (cond) { → elseif cond then
    s = s:gsub("}%s*else%s*if%s*%(([^)]+)%)%s*{", "elseif %1 then")
    -- } else { → else
    s = s:gsub("}%s*else%s*{", "else")
    -- for (var i = 0; i < n; i++) { → for i = 0, n - 1 do
    s = s:gsub("for%s*%(%s*local%s+(%w+)%s*=%s*(%d+)%s*;%s*%1%s*<%s*([^;]+)%s*;%s*%1[%+%-%-%+%+]+%)%s*{",
        function(_, name, start, stop) return "for " .. name .. " = " .. start .. ", (" .. stop .. ") - 1 do" end)
    s = s:gsub("for%s*%(([^)]+)%)%s*{", "for %1 do")
    -- while (cond) { → while cond do
    s = s:gsub("while%s*%(([^)]+)%)%s*{", "while %1 do")
    -- Object literal { key: value } → { key = value }
    s = s:gsub("([%w_]+):", "%1 =")
    -- Closing braces → end
    s = s:gsub("}", "\nend")
    -- return at end of function
    -- Array access x[0] stays same in Lua
    -- String methods: .length → #str (can't do automatically)
    -- Math.random() → math.random()
    -- Math.floor() → math.floor()
    s = s:gsub("Math%.", "math.")
    s = s:gsub("Math", "math")
    -- JSON.parse / JSON.stringify
    s = s:gsub("JSON%.parse", "textutils.unserialize")
    s = s:gsub("JSON%.stringify", "textutils.serialize")
    return s
end

local function runScript(scriptText, app)
    if not scriptText or trim(scriptText) == "" then return true end
    local env = {}
    env.print = function(...) makeConsole(app).log(nil, ...) end
    env.tostring = tostring
    env.tonumber = tonumber
    env.type = type
    env.pairs = pairs
    env.ipairs = ipairs
    env.table = {insert=table.insert, remove=table.remove, concat=table.concat, sort=table.sort}
    env.math = math
    env.string = string
    env.os = {clock=os.clock, time=os.time, day=os.day}
    env.document = makeDocument(app)
    env.console = makeConsole(app)
    env.alert = function(msg) app.showAlert(tostring(msg)) end
    env.navigate = function(url) app.navigate(tostring(url)) end
    env.setTimeout = function(fn, ms) return API.setTimeout((ms or 0) / 1000, fn) end
    env.clearTimeout = function(id) API.clearTimeout(id) end

    -- Try Lua first, then JS transpile
    local code = scriptText
    local fn, err
    if _VERSION == "Lua 5.1" and loadstring then
        fn, err = loadstring(code, "browser:script")
        if not fn then
            code = transpileJS(scriptText)
            fn, err = loadstring(code, "browser:js")
        end
        if fn and setfenv then setfenv(fn, env) end
    else
        fn, err = load(code, "browser:script", "t", env)
        if not fn then
            code = transpileJS(scriptText)
            fn, err = load(code, "browser:js", "t", env)
        end
    end
    if not fn then
        app.setStatus("Script error: " .. tostring(err))
        return false
    end
    local ok, res = pcall(fn)
    if not ok then
        app.setStatus("Script runtime: " .. tostring(res))
        return false
    end
    return true
end


-- ============================================================
-- NETWORK / FETCH
-- ============================================================
local function fetchHTTP(url, timeout)
    timeout = timeout or 5
    if not http then return nil, "HTTP not available" end
    local ok, resp = pcall(http.get, url)
    if not ok then return nil, "HTTP error: " .. tostring(resp) end
    if not resp then return nil, "HTTP request failed" end
    local readOk, content = pcall(resp.readAll)
    if not readOk or not content then content = "" end
    pcall(resp.close)
    return content, nil
end

local function fetchRednet(siteName, app)
    local net = require("ccos.drivers.net")
    net.init()
    local serverId = nil
    local result = nil
    local err = "No site server"
    local done = false
    net.lookupSiteServerAsync(3, function(id)
        serverId = id
        if not id then done = true; return end
        net.siteResolveAsync(serverId, siteName, function(hostId)
            if not hostId then err = "Site not found"; done = true; return end
            net.siteGetAsync(hostId, siteName, "index.txt", function(content, title)
                result = content
                done = true
            end)
        end)
    end)
    -- synchronous wait with interrupt preservation
    local t = os.startTimer(6)
    while not done do
        local e, a, b = os.pullEventRaw()
        if e == "timer" and a == t then
            err = "Timeout"
            done = true
        end
        -- requeue other events so desktop stays responsive
        if not done and e ~= "timer" then os.queueEvent(e, a, b) end
    end
    return result, err
end

local function fetchFile(path)
    path = path:gsub("^file://", "")
    return API.readFile(path)
end

local function fetchURL(url, app)
    url = trim(tostring(url or ""))
    if url == "" then return nil, "Empty URL" end
    local scheme = url:match("^([a-zA-Z]+)://")
    if not scheme then
        url = "http://" .. url
        scheme = "http"
    end
    scheme = scheme:lower()
    if scheme == "http" or scheme == "https" then
        return fetchHTTP(url)
    elseif scheme == "site" then
        local name = url:gsub("^site://", ""):gsub("/.*$", "")
        return fetchRednet(name, app)
    elseif scheme == "file" then
        return fetchFile(url), nil
    end
    return nil, "Unsupported scheme: " .. scheme
end

local function extractCSS(root)
    local rules = {}
    local styles = getElementsByTag(root, "style")
    for _, el in ipairs(styles) do
        local text = flattenText(el)
        local r = parseCSS(text)
        for _, rule in ipairs(r) do table.insert(rules, rule) end
    end
    return rules
end

local function extractScripts(root)
    local scripts = {}
    local elems = getElementsByTag(root, "script")
    for _, el in ipairs(elems) do
        table.insert(scripts, flattenText(el))
    end
    return scripts
end

local function resolveURL(base, rel)
    if rel:find("://") then return rel end
    if startsWith(rel, "//") then
        local scheme = base:match("^([a-zA-Z]+)://") or "http"
        return scheme .. ":" .. rel
    end
    if startsWith(rel, "/") then
        local host = base:match("^(https?://[^/]+)")
        return (host or "") .. rel
    end
    local dir = base:match("^(.*)/") or ""
    return dir .. "/" .. rel
end

local function loadImageForElement(el, baseURL, app)
    if el.tag ~= "img" then return end
    local src = el.attrs.src
    if not src then return end
    local url = resolveURL(baseURL, src)
    local scheme = url:match("^([a-zA-Z]+)://")
    if scheme == "http" or scheme == "https" then
        local content = fetchHTTP(url, 3)
        if content then
            -- Save temp and load via image API
            local tmp = "/tmp/minibrowser_img_" .. tostring(os.clock()):gsub("%.", "_")
            API.writeFile(tmp, content)
            local img = API.loadImage(tmp)
            if img then
                el._loadedImage = {pixels=img[1], w=img[2], h=img[3]}
            end
        end
    elseif scheme == "file" then
        local img = API.loadImage(url:gsub("^file://", ""))
        if img then el._loadedImage = {pixels=img[1], w=img[2], h=img[3]} end
    end
end


-- ============================================================
-- MAIN APPLICATION
-- ============================================================
local CONFIG_PATH = "/ccos/config/minibrowser.cfg"
local MAX_HISTORY = 50

local function loadConfig()
    local cfg = {history={}, bookmarks={}}
    local content = API.readFile(CONFIG_PATH)
    if content then
        local ok, parsed = pcall(textutils.unserialize, content)
        if ok and type(parsed) == "table" then
            cfg.history = parsed.history or {}
            cfg.bookmarks = parsed.bookmarks or {}
        end
    end
    return cfg
end

local function saveConfig(cfg)
    API.ensureDir(CONFIG_PATH)
    API.writeFile(CONFIG_PATH, textutils.serialize(cfg))
end

local function appMiniBrowser()
    local cfg = loadConfig()
    local app = {}
    app.win = nil
    app.domRoot = nil
    app.cssRules = {}
    app.scripts = {}
    app.url = ""
    app.title = "Mini Browser"
    app.status = "Ready"
    app.busy = false
    app.scrollY = 0
    app.maxScroll = 0
    app.history = cfg.history or {}
    app.bookmarks = cfg.bookmarks or {}
    app.historyIndex = #app.history + 1
    app.contentW = 200
    app.contentH = 120
    app.needsLayout = true
    app.alertMsg = nil
    app.alertWin = nil
    app.focusedInput = nil
    app.inputBuffers = {}  -- element -> text

    BrowserState = app

    local wx, wy, ww, wh = API.fitWindow(360, 220)
    app.win = API.window("Mini Browser", wx, wy, ww, wh)
    if not app.win then return end
    app.contentW = ww - 6
    app.contentH = wh - 21 - 18  -- minus chrome and status

    function app.setStatus(msg)
        app.status = tostring(msg)
        API.redrawContent(app.win)
    end

    function app.invalidateLayout()
        app.needsLayout = true
        API.redrawContent(app.win)
    end

    function app.navigate(url, addHistory)
        url = trim(tostring(url or ""))
        if url == "" then return end
        app.busy = true
        app.setStatus("Loading " .. url .. "...")
        app.url = url
        app.focusedInput = nil
        app.inputBuffers = {}

        local content, err = fetchURL(url, app)
        app.busy = false
        if not content then
            app.domRoot = normalizeRoot(parseHTML("<h1>Error</h1><p>Failed to load: " .. tostring(err) .. "</p>"))
            app.url = url
            app.setStatus("Error: " .. tostring(err))
        else
            -- Limit size
            if #content > 64000 then content = content:sub(1, 64000) .. "\n<!-- truncated -->" end
            app.domRoot = normalizeRoot(parseHTML(content))
            app.url = url
            app.title = "Mini Browser - " .. url
            -- extract css
            app.cssRules = extractCSS(app.domRoot)
            computeStyles(app.domRoot, app.cssRules)
            -- load images
            local imgs = getElementsByTag(app.domRoot, "img")
            for _, img in ipairs(imgs) do loadImageForElement(img, url, app) end
            -- layout
            app.needsLayout = true
            -- run scripts
            app.scripts = extractScripts(app.domRoot)
            for _, script in ipairs(app.scripts) do runScript(script, app) end
            app.setStatus("Loaded " .. url)
        end

        if addHistory ~= false then
            table.insert(app.history, url)
            if #app.history > MAX_HISTORY then table.remove(app.history, 1) end
            app.historyIndex = #app.history + 1
            saveConfig({history=app.history, bookmarks=app.bookmarks})
        end
        app.scrollY = 0
        app.invalidateLayout()
    end

    function app.goBack()
        if app.historyIndex > 2 then
            app.historyIndex = app.historyIndex - 1
            app.navigate(app.history[app.historyIndex - 1], false)
        end
    end

    function app.goForward()
        if app.historyIndex <= #app.history then
            local url = app.history[app.historyIndex]
            app.historyIndex = app.historyIndex + 1
            app.navigate(url, false)
        end
    end

    function app.reload()
        if app.url ~= "" then app.navigate(app.url, false) end
    end

    function app.showAlert(msg)
        app.alertMsg = tostring(msg)
        app.alertWin = D.inputDialog("Alert", tostring(msg), "", function()
            app.alertMsg = nil
            app.alertWin = nil
        end)
    end

    function app.openURLDialog()
        D.inputDialog("Open URL", "Address:", app.url or "http://", function(url)
            if url then app.navigate(url) end
        end)
    end

    function app.addBookmark()
        if app.url == "" then return end
        D.inputDialog("Add Bookmark", "Name:", app.title:gsub("^Mini Browser %- ", ""), function(name)
            if name then
                table.insert(app.bookmarks, {name=name, url=app.url})
                saveConfig({history=app.history, bookmarks=app.bookmarks})
                app.setStatus("Bookmark added")
            end
        end)
    end

    function app.showBookmarks()
        local html = {"<h1>Bookmarks</h1><ul>"}
        for _, bm in ipairs(app.bookmarks) do
            table.insert(html, '<li><a href="' .. bm.url .. '">' .. bm.name .. '</a></li>')
        end
        table.insert(html, "</ul>")
        app.domRoot = normalizeRoot(parseHTML(table.concat(html, "\n")))
        app.cssRules = extractCSS(app.domRoot)
        computeStyles(app.domRoot, app.cssRules)
        app.url = "about:bookmarks"
        app.needsLayout = true
        app.scrollY = 0
        app.setStatus("Bookmarks")
        API.redrawContent(app.win)
    end

    function app.showHistory()
        local html = {"<h1>History</h1><ul>"}
        for i = #app.history, 1, -1 do
            local u = app.history[i]
            table.insert(html, '<li><a href="' .. u .. '">' .. u .. '</a></li>')
        end
        table.insert(html, "</ul>")
        app.domRoot = normalizeRoot(parseHTML(table.concat(html, "\n")))
        app.cssRules = extractCSS(app.domRoot)
        computeStyles(app.domRoot, app.cssRules)
        app.url = "about:history"
        app.needsLayout = true
        app.scrollY = 0
        app.setStatus("History")
        API.redrawContent(app.win)
    end

    function app.performClick(el)
        if not el then return end
        -- input focus
        if el.tag == "input" then
            app.focusedInput = el
            local buf = app.inputBuffers[el] or (el.attrs.value or "")
            D.inputDialog("Input", el.attrs.placeholder or "Enter value:", buf, function(val)
                if val ~= nil then
                    app.inputBuffers[el] = val
                    el.attrs.value = val
                    if el._onchange then pcall(el._onchange, makeElementWrapper(el, app)) end
                end
                app.focusedInput = nil
                app.invalidateLayout()
            end)
            return
        end
        -- button/link click handlers
        if el._onclick then
            pcall(el._onclick, makeElementWrapper(el, app))
        end
        if el.tag == "a" and el.attrs.href then
            app.navigate(el.attrs.href)
        elseif el.tag == "button" and el.attrs.onclick then
            -- already handled
        end
    end

    local function doLayout()
        if not app.domRoot then return end
        app.contentW = app.win.cw - 6
        app.contentH = app.win.ch - 21 - 18
        layoutElement(app.domRoot, {availW=app.contentW, availH=app.contentH})
        applyGlobalOffset(app.domRoot, 0, 0)
        local rootH = app.domRoot.layout and app.domRoot.layout.h or 0
        app.maxScroll = math.max(0, rootH - app.contentH)
        app.needsLayout = false
    end

    app.win.onDraw = function(_, cx, cy, cw, ch)
        -- Chrome
        local btnH = 14
        local addrY = cy + 2
        local addrH = 14
        button(cx + 2, addrY, 24, "<")
        button(cx + 28, addrY, 24, ">")
        button(cx + 54, addrY, 30, "Reload")
        button(cx + 86, addrY, 30, "URL")
        button(cx + 118, addrY, 40, "Bookmarks")

        local addrX = cx + 160
        local addrW = math.max(40, cw - 160 - 4)
        R.drawW95Sunken(addrX, addrY, addrW, addrH)
        drawText(addrX + 4, addrY + 3, clip(app.url, addrW - 8), K.BLACK, K.GRAY)

        -- Content area
        local contentY = cy + 20
        local contentH = ch - 20 - 14
        R.drawW95Sunken(cx, contentY, cw, contentH)

        if app.domRoot then
            if app.needsLayout then doLayout() end
            local contentAreaX = cx + 2
            local contentAreaY = contentY + 2
            local clipRect = {x=contentAreaX, y=contentAreaY, w=cw - 4, h=contentH - 4}
            renderElement(app.domRoot, -contentAreaX, app.scrollY - contentAreaY, clipRect)
        else
            drawText(cx + 8, contentY + 8, "Enter a URL to start browsing.", K.DGRAY, K.GRAY)
        end

        -- Status bar
        drawText(cx + 4, cy + ch - 10, app.status, K.DGRAY, K.GRAY, cw - 8)
    end

    app.win.onClick = function(_, mx, my)
        local cx, cy, cw, ch = 0, 0, app.win.cw, app.win.ch
        -- Check chrome buttons
        if my >= 2 and my < 16 then
            if mx >= 2 and mx < 26 then app.goBack(); return
            elseif mx >= 28 and mx < 52 then app.goForward(); return
            elseif mx >= 54 and mx < 84 then app.reload(); return
            elseif mx >= 86 and mx < 116 then app.openURLDialog(); return
            elseif mx >= 118 and mx < 158 then app.showBookmarks(); return
            end
        end
        -- Content area click
        local contentY = 20
        local contentH = ch - 20 - 14
        if my >= contentY + 2 and my < contentY + contentH - 2 then
            local clickX = mx - 2
            local clickY = my - (contentY + 2) + app.scrollY
            if app.domRoot then
                local el = hitTest(app.domRoot, clickX, clickY, 0, app.scrollY)
                if el then app.performClick(el) end
            end
        end
    end

    app.win.onScroll = function(_, dir, mx, my)
        local step = 24
        if dir < 0 then app.scrollY = math.max(0, app.scrollY - step)
        else app.scrollY = math.min(app.maxScroll, app.scrollY + step) end
        API.redrawContent(app.win)
    end

    app.win.onKey = function(_, k, ch)
        if k == keys.f5 then app.reload()
        elseif k == keys.escape then API.close(app.win)
        elseif k == keys.up then app.scrollY = math.max(0, app.scrollY - 24); API.redrawContent(app.win)
        elseif k == keys.down then app.scrollY = math.min(app.maxScroll, app.scrollY + 24); API.redrawContent(app.win)
        elseif k == keys.pageUp then app.scrollY = math.max(0, app.scrollY - app.contentH + 10); API.redrawContent(app.win)
        elseif k == keys.pageDown then app.scrollY = math.min(app.maxScroll, app.scrollY + app.contentH - 10); API.redrawContent(app.win)
        elseif k == keys.home then app.scrollY = 0; API.redrawContent(app.win)
        elseif k == keys["end"] then app.scrollY = app.maxScroll; API.redrawContent(app.win)
        elseif ch == "l" or ch == "L" then app.openURLDialog()
        elseif ch == "b" or ch == "B" then app.addBookmark()
        elseif ch == "h" or ch == "H" then app.showHistory()
        end
    end

    _G._minibrowser_app = app  -- debug hook for testing/inspection

    -- initial page
    if #app.history > 0 then
        app.navigate(app.history[#app.history], false)
    else
        app.domRoot = normalizeRoot(parseHTML([[
<h1>Mini Browser</h1>
<p>Welcome to the lightweight browser for CCOS.</p>
<p>Press <b>L</b> to open a URL, <b>B</b> for bookmark, <b>H</b> for history.</p>
<p>Example: <a href="http://example.com">example.com</a></p>
]]))
        app.cssRules = extractCSS(app.domRoot)
        computeStyles(app.domRoot, app.cssRules)
        app.url = "about:home"
        app.invalidateLayout()
    end
end

return {name = "Mini Browser", icon = "minibrowser", run = appMiniBrowser}
