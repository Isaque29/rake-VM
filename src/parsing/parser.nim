import ../lexing/tokenizer
import ../common/token

proc parse* (src: string): void =
    var tz: Tokenizer = newTokenizer(src)
    var toks: seq[Token] = tz.tokenize()
    for t in toks:
        echo t.line, ":", t.col, " ", $t.kind, " -> '", t.lexeme, "'"
