-- vim:sw=4:sts=4

---
-- Format a 16 bit value into two octal bytes in high/low order.
--
function format_2bytes(val)
    return string.format("\\%03o\\%03o", bit.band(bit.rshift(val, 8), 255),
	bit.band(val, 255))
end

local function count_bits(v)
    local n = 0
    while v > 0 do
	n = n + 1
	v = bit.rshift(v, 1)
    end
    return n
end

---
-- type_idx are assigned to the types in use sorted by their frequency, i.e.
-- most used types get a low type_idx.  This is good, as lower type_idx can
-- be encoded with less bytes.
--
-- In practice, this results in a very slightly smaller total size.
--
function count_const_usage()

    -- uncomment the following line to enable the histogram.
--    local histo, max_n = { [0]=0 }, 0

    for k, enum in pairs(xml.enum_values) do
	t = typedefs[enum.context]
	assert(t)

	-- follow redirections
	while t.enum_redirect do
	    t = typedefs[t.enum_redirect]
	    assert(t)
	end

	if t.in_use and not t.no_good then
	    if not (t.counter >= 0) then
		error("Unused const type " .. tostring(t.full_name)
		    .. " for constant " .. tostring(k))
	    end
	    t.counter = (t.counter or 0) + 1
	    if histo and type(enum.val) == "number" then
		local n = count_bits(enum.val)
		while max_n < n do
		    max_n = max_n + 1
		    histo[max_n] = 0
		end
		histo[n] = histo[n] + 1
	    end
	end
    end

    -- Show the histogram of bits
    if histo then
	local sum = 0
	for i = 0, max_n do
	    sum = sum + histo[i]
	end

	local tally = 0
	print("Histogram of Constants\nBits   Count    Tally    %")
	for i = 0, max_n do
	    tally = tally + histo[i]
	    print(string.format(" %2d %8d %8d %3.0f%%", i, histo[i],
		tally, tally * 100 / sum))
	end
    end
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
enum_largetype = 0	    -- number of 16 bit type numbers stored
enum_distincttypes = 0
enum_typesseen = {}
enum_next_type_idx_idx = 0

function encode_byte(val)
    return string.format("\\%03o", val)
end

-- first version with 3 flag bits in the first byte: has_type, is_string
-- and is_negative, and 5 bits of data or type number.
function encode_enum_v1(name, val, type_idx)
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
	enum_rawdata = enum_rawdata + 1
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
    return string.format("%s,%s%s%s", name, encode_byte(c), extra, s)
end

---
-- Second version.  First byte with 6 bits of data and a 2-bit indicator for
-- no type, 8 bit type, 16 bit type or string.  negative values have bit 15
-- set in their type (which may be zero); this is very scarce.
--
function encode_enum_v2(name, val, type_idx)

    local first, buf, t, pos

    buf = {}
    type_idx = type_idx or 0
    enum_count = enum_count + 1
    t = type(val)

    if t == "number" and val < 0 then
	type_idx = bit.bor(type_idx, 0x8000)
	val = -val
	enum_negative = enum_negative + 1
    end

    if t == "string" then
	assert(type_idx == 0)
	first = 0xC0
	buf[#buf + 1] = val
	enum_rawdata = enum_rawdata + #val - 1
	enum_strings = enum_strings + 1
    elseif t == "number" then
	if type_idx == 0 then
	    first = 0
	else
	    enum_typenr = enum_typenr + 1
	    if not enum_typesseen[type_idx] then
		enum_distincttypes = enum_distincttypes + 1
		enum_typesseen[type_idx] = true
	    end
	    if type_idx > 0xff then
		buf[1] = encode_byte(bit.rshift(type_idx, 8))
		type_idx = bit.band(type_idx, 0xff)
		enum_largetype = enum_largetype + 1
		first = 0x80
	    else
		first = 0x40
	    end
	    buf[#buf + 1] = encode_byte(type_idx)
	end

	-- the first byte contains the high 6 bits of the value.
	pos = #buf + 1
	while val > 0x3f do
	    table.insert(buf, pos, encode_byte(bit.band(val, 255)))
	    val = bit.rshift(val, 8)
	end

	first = bit.bor(first, val)
    else
	error("Unhandled type: " .. t)
    end

    enum_rawdata = enum_rawdata + 1 + #buf
    return string.format("%s,%s%s", name, encode_byte(first), table.concat(buf))
end

---
-- Third version: always have two bytes at the beginning with the type idx,
-- as most entries have a type_idx anyway.  10 bits for type_idx, 1
-- bit for negative flag, 5 bits for high bits of value.
--
function encode_enum_v3(name, val, type_idx)

    local first, buf, s, t

    buf = {}
    type_idx = type_idx or 0

    enum_count = enum_count + 1
    t = type(val)

    if t == "string" then
	assert(type_idx == 0)
	first = 0xffff
	buf[#buf + 1] = val
	enum_rawdata = enum_rawdata + #val - 1
	enum_strings = enum_strings + 1
    elseif t == "number" then
	assert(type_idx <= 0x03ff)
	if type_idx ~= 0 then
	    enum_typenr = enum_typenr + 1
	end
	first = type_idx

	if val < 0 then
	    first = bit.bor(first, 0x0400)
	    val = -val
	    enum_negative = enum_negative + 1
	end
	
	while val > 0x1f do
	    table.insert(buf, 1, encode_byte(bit.band(val, 0xff)))
	    val = bit.rshift(val, 8)
	end

	-- store high 5 bits in first short integer
	first = bit.bor(first, bit.lshift(val, 11))
    else
	error("Unhandled type in encode_enum: " .. t)
    end

    -- each item in buf results in one byte
    enum_rawdata = enum_rawdata + 2 + #buf
    return string.format("%s,%s%s%s", name,
	encode_byte(bit.rshift(first, 8)),
	encode_byte(bit.band(first, 0xff)),
	table.concat(buf))
end

---
-- Version 4.  Most constants have a type_idx, but there are not so many
-- distinct type_idx in use.  Therefore, build a table with 16 bit entries,
-- each containing a type_idx.  The entries only contain an index number to
-- this table.
--
-- But as most type_idx fit into 8 bits, v2 is equally efficient, but this
-- encoding here needs an extra type_idx table, which makes it larger.
--
function encode_enum_v4(name, val, type_idx)

    local buf, t, type_idx_idx, first

    buf = { name, "," }
    type_idx = type_idx or 0

    enum_count = enum_count + 1
    t = type(val)

    -- strings are stored with a type_idx_idx of 0x7f.
    if t == "string" then
	assert(type_idx == 0)
	buf[#buf + 1] = encode_byte(0xff)   -- type for string
	buf[#buf + 1] = val
	enum_rawdata = enum_rawdata + #val - 1
	enum_strings = enum_strings + 1
    elseif t == "number" then

	-- flag for negative value.
	if val < 0 then
	    val = -val
	    type_idx = bit.bor(type_idx, 0x8000)
	    enum_negative = enum_negative + 1
	end

	-- store the type as first byte; 0=none
	if type_idx ~= 0 then
	    enum_typenr = enum_typenr + 1
	    type_idx_idx = enum_typesseen[type_idx]
	    if not type_idx_idx then
		enum_next_type_idx_idx = enum_next_type_idx_idx + 1
		type_idx_idx = enum_next_type_idx_idx
		assert(type_idx_idx < 0x80)
		enum_distincttypes = enum_distincttypes + 1
		enum_typesseen[type_idx] = type_idx_idx
		enum_rawdata = enum_rawdata + 2
	    end
	    buf[#buf + 1] = encode_byte(bit.bor(type_idx_idx, 0x80))
	end

	-- the first byte contains the high 7 bits of the value.
	t = #buf + 1
	while val >= 0x80 do
	    table.insert(buf, t, encode_byte(bit.band(val, 0xff)))
	    val = bit.rshift(val, 8)
	end
	table.insert(buf, t, encode_byte(bit.bor(val, 0x80)))
    else
	error("Unhandled type in encode_enum: " .. t)
    end

    enum_rawdata = enum_rawdata + 1 + #buf
    return table.concat(buf)
    -- return string.format("%s,%s", name, table.concat(buf))
end

encode_enum = encode_enum_v2

function enum_statistics()
    info_num("Constant Count", enum_count)
    info_num("Constant raw data bytes", enum_rawdata)
    info_num("Constant string count", enum_strings)
    info_num("Constant negative numbers", enum_negative)
    info_num("Constants with type_idx", enum_typenr)
    info_num("Constants with 16 bit type_idx", enum_largetype)
    info_num("Constants distinct types", enum_distincttypes)
end

