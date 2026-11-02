# dup, swap, discard, copy and slide.
push 1
push 2
swap
outnum
push 32
outchar
dup
add
outnum
push 32
outchar
push 3
push 4
discard
outnum
push 32
outchar
push 10
push 20
push 30
copy 2
outnum
push 32
outchar
slide 2
outnum
end
