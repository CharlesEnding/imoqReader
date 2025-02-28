import std/[dirs, files, paths, streams]

const GZIP_MAGIC: array[2, byte] = [0x1F, 0x8B]
const BLOCK_SIZE: int = 2048

proc main(filePath, outFolder: string) =
  if not fileExists(filePath.Path): raise newException(ValueError, "Input file does not exist.")
  let stream = newFileStream(filePath, fmRead)
  defer: stream.close()

  var fileIndex = 0
  var maybeMagic: array[2, byte]
  while not stream.atEnd():
    discard stream.readData(maybeMagic.addr, sizeof(maybeMagic))
    if maybeMagic == GZIP_MAGIC:
      var startOfFile: int = stream.getPosition() - sizeof(maybeMagic)
      stream.setPosition(startOfFile)

      # Seek until the next file in the buffer. Files are 2048 (BLOCK_SIZE) bytes aligned.
      var currentPosition: int = startOfFile
      while not stream.atEnd():
        currentPosition += BLOCK_SIZE
        stream.setPosition(currentPosition)
        discard stream.peekData(maybeMagic.addr, sizeof(maybeMagic))
        if maybeMagic == GZIP_MAGIC: # We've reached the next gzip file, and the end of the previous.
          break

      stream.setPosition(startOfFile)
      var fileSize: int = currentPosition - startOfFile
      var fileData: string = stream.readStr(fileSize)

      var outPath: Path = outFolder.Path / ($fileIndex & ".gz").Path
      if not dirExists(outFolder.Path): raise newException(ValueError, "Output folder does not exist.")
      var outFile: Stream = newFileStream(outPath.string, fmWrite)
      outFile.write(fileData)
      outFile.close()

      fileIndex += 1

let filePath  = "data/infection/DATA/DATA.BIN"
let outFolder = "data/infection/unpacked/"
main(filePath, outFolder)
