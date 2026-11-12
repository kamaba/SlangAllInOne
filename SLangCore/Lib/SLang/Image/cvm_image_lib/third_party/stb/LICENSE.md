stb single-file public domain libraries for C/C++
=================================================

Source:  https://github.com/nothings/stb  (Sean Barrett, nothings.org)
Fetched: 2026-11-12, from https://raw.githubusercontent.com/nothings/stb/master/
Files:   stb_image.h         v2.31  (decode: JPEG/PNG/BMP/GIF/PSD/HDR/PIC/PNM/TGA)
         stb_image_write.h   v1.17  (encode: PNG/BMP/TGA/JPEG/HDR)

License: public domain OR MIT-0 (per file header "public domain ... use at
your own risk"; upstream repo dual-licenses as public domain / MIT Zero).
No warranty implied; use at your own risk.

The two headers are vendored UNMODIFIED into this repository and compiled
inside sl_image_lib.dll (Codec/sl_image_stb.c defines the IMPLEMENTATION
macros). They are linked statically; the produced DLL is self-contained.
