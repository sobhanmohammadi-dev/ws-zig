# div and mod round towards negative infinity, like Haskell.
push -7
push 2
div
outnum
push 32
outchar
push -7
push 2
mod
outnum
push 32
outchar
push 7
push -2
div
outnum
push 32
outchar
push 7
push -2
mod
outnum
end
