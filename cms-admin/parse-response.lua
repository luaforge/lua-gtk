--
-- experiments for string parsing using a JSON like syntax
--

s = "INFO blah blah blah\nOK list follows\n\n{ foo=2, bar=string.upper('foo') }\n"

pos = 1
ok = false
while true do
	if string.sub(s, pos, pos) == "\n" then
		print "END of headers"
		break
	end
	start, stop, status, text = string.find(s, "(%u+) (.-)\n", pos)
	print("res", start, stop, status, text, "END")
	if not start then break end
	if status == "OK" then ok = true; break end
	pos = stop + 1
end

if ok then
	print "REST"
	rest = string.sub(s, stop+1)
	print("rest is", rest)
	rest, msg = loadstring("return " .. rest)
	print("rest is", rest, msg)
	setfenv(rest, { string=string, math=math })
	ok, rest = pcall(rest)
	print("rest is", ok, rest)

	if ok then
		for k,v in pairs(rest) do print(k,v) end
	end
end


