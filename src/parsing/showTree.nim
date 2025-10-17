import ../common/ast

proc printAst* (node: Ast; prefix: string = "") =
  stdout.write(prefix & $node.kind & " \"" & node.lexeme & "\"\n")
  let n = node.children.len
  for i in 0 ..< n:
    let child = node.children[i]
    let isLast = (i == n - 1)
    let branch = if isLast: "└─ " else: "├─ "
    let nextPrefix = prefix & (if isLast: "     " else: "│    ")
    stdout.write(prefix & branch)
    printAst(child, nextPrefix)

proc printRootSummary* (root: Ast) =
  stdout.write("root.kind = " & $root.kind & ", root.lexeme = \"" & root.lexeme & "\"\n")
  stdout.write("root.children.len = " & $root.children.len & "\n")
  if root.children.len > 0:
    stdout.write("child kinds: ")
    for i in 0 ..< root.children.len:
      if i > 0: stdout.write(", ")
      stdout.write($root.children[i].kind)
    stdout.write("\n")
