import ../common/ast

proc printAst*(root: Ast) =
    proc printChildren(node: Ast; prefix: string) =
        let m = node.children.len
        for i in 0 ..< m:
            let child = node.children[i]
            let isLast = (i == m - 1)
            let branch = if isLast: "└─ " else: "├─ "
            let nextPrefix = prefix & (if isLast: "   " else: "│  ")
            stdout.write(prefix & branch & $child.kind & " \"" & child.lexeme & "\"\n")
            printChildren(child, nextPrefix)

    stdout.write($root.kind & " \"" & root.lexeme & "\"\n")
    printChildren(root, "")

proc printRootSummary* (root: Ast) =
    stdout.write("root.kind = " & $root.kind & ", root.lexeme = \"" & root.lexeme & "\"\n")
    stdout.write("root.children.len = " & $root.children.len & "\n")
    if root.children.len > 0:
        stdout.write("child kinds: ")
        for i in 0 ..< root.children.len:
            if i > 0: stdout.write(", ")
            stdout.write($root.children[i].kind)
        stdout.write("\n")
