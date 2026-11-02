# A jump resolves to the first definition of a duplicated label.
jump start
label start
push 65
outchar
end
label start
push 66
outchar
end
