import std/os
import src/parsing/parser

when isMainModule:
    echo "---- Rake VM ----"

    if paramCount() < 1:
        echo readFile("version.txt")
        quit(0)
    
    var path = paramStr(1)
    if not (path.len >= 3 and path[^3 .. ^1] == ".rk"):
        echo "Invalid extension. Expected an .rk (rake) file"
        quit(1)
    
    if not fileExists(path):
        echo "The file doenst exists"
        quit(1)
    
    var source: string = readFile(path)
    parse(source)


