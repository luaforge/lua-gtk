#! /bin/sh
# Render the Logo
# Requires GhostScript.

gs -sDEVICE=png16m -sOutputFile=lua-gtk-logo.png -g128x128 \
	-dEPSFitPage -dNOPAUSE -dTextAlphaBits=4 \
	-dGraphicsAlphaBits=4 -dBATCH -dQUIET -dSAFER \
	lua-logo-label.ps
