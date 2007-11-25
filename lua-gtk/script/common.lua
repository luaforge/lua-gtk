
---
-- Format a 16 bit value into two octal bytes in high/low order.
--
function format_2bytes(val)
    return string.format("\\%03o\\%03o", bit.band(bit.rshift(val, 8), 255),
	bit.band(val, 255))
end

---
-- Compute the representation of an ENUM in the hash table.
--
function encode_enum(name, val, struct_id)
    local s = ""
    local t = type(val)

    if t == "string" then
	assert(struct_id == 0)
	s = format_2bytes(0xfffe) .. val
    elseif t == "number" then
	s = encode_enum_integer(val, struct_id)
    else
	error("unhandled type " .. type(val) .. " in encode_enum")
    end

    return string.format("%s,%s", name, s)
end

-- output an integer into a string with octal bytes, high order byte first.
-- prefix with $FFFF if negative.
function encode_enum_integer(val, struct_id)
    local s = ""
    local prefix = ""

    -- negative values are very rare.  prefix them by $FFFF.
    if val < 0 then
	val = -val
	prefix = format_2bytes(0xffff)
    end

    while val > 0 do
	s = string.format("\\%03o", bit.band(val, 255)) .. s
	val = bit.rshift(val, 8)
    end
    return prefix .. format_2bytes(struct_id) .. s
end

