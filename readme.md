# For use with IMOQ files only.

Based on work by:
* zMath3usMSF: https://github.com/zMath3usMSF/Modded-CCSFileExplorerWV
* zeroKilo:    https://github.com/zeroKilo/CCSFileExplorerWV
* NCDyson:     https://github.com/NCDyson/StudioCCS
* Al-Hydra:    https://github.com/Al-Hydra/blender_ccs_importer

This is a terse reimplementation of their reverse-engineering work.
Only 500 lines of code and easy to compile and run on linux.
Exports to glb so it can be used easily by any graphics software.

All the known structs for the CCS format are in the ccs.nim and blocks.nim files. They are mostly self-documenting. Idiosyncracies are listed in the Things to Know section.

Workflow:
1. Run unpacker to unpack data.bin into individual gzip files
2. Run `gzip -d \*.gz` to unzip the gzip files
3. Run reader to parse the ccs files and export them as glb

Not yet done:
	Commandline arguments.
	Anime object parsing.

# Building from source

1. Install the single dependency: `nimble install stb_image`
2. Compile: `nim c ccs.nim`

# File list and description

A list of files and the description of their content is available here: [files_list.txt](files_list.txt).

# Format Idiosyncracies

These are things to know for developers who want to look into the CCS format, not of any use to people who just want to use this program.

## Models

Each model has its own vertex scale. One should be careful to apply it only after the vertices have been converted to floats or there will be overflows.
The UVs are between 0 and 256 and should be normalized to 0-1.
The model transforms are stored in the dummies (position, rotation) and the model itself (scale). Dummies cannot be linked to models through the files. The information is just not there. In later iterations of the format CyberConnect2 added a binary struct to link them together but for IMOQ I suspect the information is hardcoded in the game itself. That means for specific files, the meshes are collapsed onto the origin (and in-game they will be placed correctly by the code but that's not available for our glb files). You'll see this for Mac Anu and some other towns, as well as fields (entrances, rocks, etc... are all superimposed at the origin).

## Textures

Textures are all BMP files with indexed colors (either 4bits indexed or 8bits indexed). They are stored as arrays of bytes without a header. The palette for the indexed colors is stored in a clut object.
The width and height of the texture are stored as powers of 2.
The alpha of the texture is half what it should be so it needs to be doubled before use (taking care not to overflow the byte for values > 0x7F).
