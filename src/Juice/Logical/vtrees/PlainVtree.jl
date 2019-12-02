using DataStructures
using Random

#############
# PlainVtree
#############

"Root of the plain vtree node hierarchy"
abstract type PlainVtreeNode <: VtreeNode end

struct PlainVtreeLeafNode <: PlainVtreeNode
    var::Var
end

mutable struct PlainVtreeInnerNode <: PlainVtreeNode
    left::PlainVtreeNode
    right::PlainVtreeNode
    variables::Vector{Var}
end

const PlainVtree = AbstractVector{<:PlainVtreeNode}

#####################
# Constructor
#####################

function PlainVtreeInnerNode(left::PlainVtreeNode, right::PlainVtreeNode)
    @assert isempty(intersect(variables(left), variables(right)))
    PlainVtreeInnerNode(left, right, [variables(left); variables(right)])
end

function PlainVtreeLeafNode(vars::Vector{Var})
    @assert length(vars) == 1
    PlainVtreeLeafNode(vars[1])
end

PlainVtreeNode(v::Var) = PlainVtreeLeafNode(v)
PlainVtreeNode(left::PlainVtreeNode, right::PlainVtreeNode) = PlainVtreeInnerNode(left, right)


#####################
# Traits
#####################

@inline NodeType(::PlainVtreeLeafNode) = Leaf()
@inline NodeType(::PlainVtreeInnerNode) = Inner()

#####################
# Methods
#####################

@inline children(n::PlainVtreeInnerNode) = [n.left, n.right]

isleaf(n::PlainVtreeLeafNode) = true
isleaf(n::PlainVtreeInnerNode) = false

variables(n::PlainVtreeLeafNode) = [n.var]
variables(n::PlainVtreeInnerNode) = n.variables

num_variables(n::PlainVtreeLeafNode) = 1
num_variables(n::PlainVtreeInnerNode) = length(n.variables)

"""
Return the leftmost child.
"""
function left_most_child(root::PlainVtreeNode)::PlainVtreeLeafNode
    while !(root isa PlainVtreeLeafNode)
        root = root.left
    end
    root
end

"""
Order the nodes in preorder
"""
function pre_order_traverse(root::PlainVtreeNode)::PlainVtree
    # Running DFS
    visited = Vector{PlainVtreeNode}()
    stack = Stack{PlainVtreeNode}()
    push!(stack, root)

    while !isempty(stack)
        cur = pop!(stack)
        push!(visited, cur)

        if cur isa PlainVtreeInnerNode
            push!(stack, cur.left)
            push!(stack, cur.right)
        end
    end
    reverse(visited)
end

"""
Construct PlainVtree top town, using method specified by split_method.
"""
function construct_top_down(vars::Vector{Var}, split_method)::PlainVtreeNode
    root(
        construct_top_down_root(vars,split_method))
end

function construct_top_down_root(vars::Vector{Var}, split_method)::PlainVtreeNode
    @assert !isempty(vars) "Cannot construct a vtree with zero variables"
    if length(vars) == 1
        PlainVtreeLeafNode(vars)
    else
        (X, Y) = split_method(vars)
        prime = construct_top_down_root(X, split_method)
        sub = construct_top_down_root(Y, split_method)
        PlainVtreeInnerNode(prime, sub)
    end
end


"""
Construct PlainVtree bottom up, using method specified by combine_method!.
"""
function construct_bottom_up(vars::Vector{Var}, combine_method!)::PlainVtree
    vars = copy(vars)
    ln = Vector{PlainVtreeNode}()
    node_cache = Dict{Var, PlainVtreeNode}() # map from variable to *highest* level node

    "1. construct leaf node"
    for var in vars
        n = PlainVtreeLeafNode(var)
        node_cache[var] = n
        push!(ln, n)
    end

    "2. construct inner node"
    while length(vars) > 1
        matches = combine_method!(vars) # vars are mutable
        for (left, right) in matches
            n = PlainVtreeInnerNode(node_cache[left], node_cache[right])
            node_cache[left] = node_cache[right] = n
            push!(ln, n)
        end
    end

    "3. clean up"
    root(ln[end])
end

import ..Utils.isequal_local
"""
Compare whether two vtree nodes are locally equal (enables `equals` and `equals_unordered` from Utils)
"""
isequal_local(leaf1::PlainVtreeNode, leaf2::PlainVtreeNode)::Bool = false #default
isequal_local(leaf1::PlainVtreeLeafNode, leaf2::PlainVtreeLeafNode)::Bool = 
    (leaf1.var == leaf2.var)
isequal_local(inner1::PlainVtreeInnerNode, inner2::PlainVtreeInnerNode)::Bool = 
    isequal(variables(inner1), variables(inner2))