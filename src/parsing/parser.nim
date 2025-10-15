import ../lexing/tokenizer
import ../common/token
import ../common/kind

proc parse* (src: string): void =
    var tz: Tokenizer = newTokenizer(src)
    var toks: seq[Token] = tz.tokenize()
    for t in toks:
        if t.kind == tkNewLine:
            echo '\n'
            continue
        echo t.line, ":", t.col, " ", $t.kind, " -> '", t.lexeme, "'"
