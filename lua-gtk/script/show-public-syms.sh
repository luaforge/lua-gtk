#! /bin/sh

echo $0
cd build/linux-i386
for i in *.o; do
	echo $i
	nm $i | grep " [DTR] " | grep -v thunk
done

