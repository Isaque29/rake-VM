import kind

type
    Token* = object
        kind*: Kind
        lexeme*: string
        startPos*: int
        len*: int
        line*: int
        col*: int
