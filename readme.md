# For use with IMOQ files only.

Based on work by:
* zMath3usMSF: https://github.com/zMath3usMSF/Modded-CCSFileExplorerWV
* zeroKilo:    https://github.com/zeroKilo/CCSFileExplorerWV
* NCDyson:     https://github.com/NCDyson/StudioCCS

This is a terse reimplementation of their reverse-engineering work.
Less than 1000 lines of code and easy to compile and run on linux.
Exports to glb so it can be used easily by any graphics software.

All the known structs for the CCS format are in the ccs.nim and blocks.nim files. They are self-documenting.

Workflow:
1. Run unpacker to unpack data.bin into individual gzip files
2. Run `gzip "\*.gz"` to unzip the gzip files
3. Run reader to parse the ccs files and export them as glb

Not yet done:
	Commandline arguments.
	Anime object parsing.