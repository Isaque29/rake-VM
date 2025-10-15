import kind, span

type
    Ast* = object
        kind*: Kind
        lexeme*: string
        children*: seq[Ast]
        span*: Span
