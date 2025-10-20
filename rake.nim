import std/os
import src/parsing/parser
import src/parsing/showTree
import src/codegen/compiler
import src/lexing/tokenizer
import src/common/token

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

    var tz: Tokenizer = newTokenizer(source)
    var toks: seq[Token] = tz.tokenize()
    
    # stdout.write("=== tokens ===\n")
    # for i, t in toks:
    #     stdout.write($i & "  kind=" & $t.kind & " lex='" & t.lexeme & "' pos=" & $t.startPos & "\n")
    # stdout.write("tokens.len = " & $toks.len & "\n")
    # stdout.write("=============\n")

    var p: Parser = newParser(toks)
    var astProgram = p.parseProgram()
    astProgram.printAst()
    astProgram.printRootSummary()

    echo "---- Compilation ----"
    let generatedCode = compiler.compile(astProgram)
    echo generatedCode
