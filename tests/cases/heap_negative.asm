# DELIBERATE DEVIATION
# Store takes the address below the value, so push the address first.
# The reference recurses forever on a negative address; this interpreter
# reports an error instead of hanging.
push -1
push 5
store
end
