-- vim:sw=4:sts=4

---
-- Format a 16 bit value into two octal bytes in high/low order.
--
function format_2bytes(val)
    return string.format("\\%03o\\%03o", bit.band(bit.rshift(val, 8), 255),
	bit.band(val, 255))
end

---
-- Compute the representation of an ENUM in the hash table.  The format is
-- described in doc/README.
--

enum_count = 0
enum_rawdata = 0
enum_strings = 0
enum_negative = 0
enum_typenr = 0

function encode_byte(val)
    return string.format("\\%03o", val)
end

function encode_enum(name, val, type_idx)
    local s = ""
    local extra = ""
    local t = type(val)
    local c = 0		-- first byte
    local have_type = false

    enum_count = enum_count + 1

    -- if type_idx is given, set high bit of flag and encode it
    if type_idx and type_idx ~= 0 then
	extra = encode_byte(bit.band(type_idx, 255))
	c = 0x80 + bit.rshift(type_idx, 8)
	have_type = true
	enum_typenr = enum_typenr + 1
    end

    -- if string, simply append the string.
    if t == "string" then
	enum_strings = enum_strings + 1
	c = bit.bor(c, 0x40)
	s = val
	enum_rawdata = enum_rawdata + #val
    elseif t == "number" then
	-- if type_idx is not set, use some bits of the first byte
	limit = have_type and 0 or 0x1f

	if val < 0 then
	    c = bit.bor(c, 0x20)
	    val = -val
	    enum_negative = enum_negative + 1
	end

	while val > limit do
	    s = encode_byte(bit.band(val, 255)) .. s
	    val = bit.rshift(val, 8)
	    enum_rawdata = enum_rawdata + 1
	end

	-- or the remaining bits into the first byte.
	c = bit.bor(c, val)
    else
	error("unhandled type " .. type(val) .. " in encode_enum")
    end

    enum_rawdata = enum_rawdata + 1
    return string.format("%s,%s", name, encode_byte(c) .. extra .. s)
end

function enum_statistics()
    info_num("Enum Count", enum_count)
    info_num("Enum raw data bytes", enum_rawdata)
    info_num("Enum string count", enum_strings)
    info_num("Enum negative numbers", enum_negative)
    info_num("Enums with type_idx", enum_typenr)
end

