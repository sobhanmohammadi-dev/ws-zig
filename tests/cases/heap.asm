# Heap store and retrieve, including zero padding up to a high address.
push 0
push 99
store
push 0
retrieve
outnum
push 32
outchar
push 1000
push 7
store
push 1000
retrieve
outnum
push 32
outchar
push 1
retrieve
outnum
end
