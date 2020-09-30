export smooth, forget, propagate_constants, deepcopy, condition, replace_node, 
    split, clone, merge, split_candidates, random_split, split_step, struct_learn,
    clone_candidates , clone_step

"""
    smooth(root::Node)::Node
    
Create an equivalent smooth circuit from the given circuit.
"""
function smooth(root::Node)::Node
    lit_nodes = canonical_literals(root)
    f_con(n) = (n, BitSet())
    f_lit(n) = (n, BitSet(variable(n)))
    f_a(n, call) = begin
        parent_scope = BitSet()
        smooth_children = Vector{Node}(undef, num_children(n))
        map!(smooth_children, children(n)) do child
            (smooth_child, scope) = call(child)
            union!(parent_scope, scope)
            smooth_child
        end
        (conjoin([smooth_children...]; reuse=n), parent_scope)
    end
    f_o(n, call) = begin
        parent_scope = mapreduce(c -> call(c)[2], union, children(n))
        smooth_children = Vector{Node}(undef, num_children(n))
        map!(smooth_children, children(n)) do child
            (smooth_child, scope) = call(child)
            smooth_node(smooth_child, setdiff(parent_scope, scope), lit_nodes)
        end
        return (disjoin([smooth_children...]; reuse=n), parent_scope)
    end
    foldup(root, f_con, f_lit, f_a, f_o, Tuple{Node, BitSet})[1]
end

"""
    smooth_node(node::Node, missing_scope, lit_nodes)

Return a smooth version of the node where 
the `missing_scope` variables are added to the scope, using literals from `lit_nodes`
"""
function smooth_node(node::Node, missing_scope, lit_nodes)
    if isempty(missing_scope)
        return node # avoid adding unnecessary nodes
    else
        get_lit(l) = get!(() -> compile(node, l), lit_nodes, l)
        ors = map(collect(missing_scope)) do v
            lit = var2lit(Var(v))
            lit_node = get_lit(lit)
            not_lit_node = get_lit(-lit)
            disjoin([lit_node, not_lit_node]; reuse=node)
        end
        conjoin([node, ors...]; reuse=node)
    end
end


"""
    forget(root::Node, is_forgotten::Function)::Node

Forget variables from the circuit.
Warning: this may or may not destroy the determinism property.
"""
function forget(root::Node, is_forgotten::Function, )::Node
    (_, true_node) = canonical_constants(root)
    if isnothing(true_node)
        true_node = compile(typeof(root), true)
    end
    f_con(n) = n
    f_lit(n) = is_forgotten(variable(n)) ? true_node : n
    f_a(n, cn) = conjoin([cn...]; reuse=n) # convert type of cn
    f_o(n, cn) = disjoin([cn...]; reuse=n)
    foldup_aggregate(root, f_con, f_lit, f_a, f_o, Node)
end


"""
    propagate_constants(root::Node)

Remove all constant leafs from the circuit
"""
function propagate_constants(root::Node; remove_unary=false)
    (false_node, true_node) = canonical_constants(root)
    if isnothing(true_node)
        true_node = compile(typeof(root), true)
    end
    if isnothing(false_node)
        false_node = compile(typeof(root), false)
    end
    f_con(n) = n
    f_lit(n) = n
    f_a(n, cn) = begin
        if any(c -> isfalse(c), cn)
            false_node
        else
            T = promote_type(typeof(n), typeof.(cn)...)
            proped_children = convert(Vector{T}, filter(c -> !istrue(c), cn))
            if isempty(proped_children)
                return true_node
            elseif remove_unary && issingle(proped_children)
                return proped_children[1]
            else
                return conjoin(proped_children; reuse=n)
            end
        end
    end
    f_o(n, cn) = begin
        if any(c -> istrue(c), cn)
            true_node
        else
            T = promote_type(typeof(n), typeof.(cn)...)
            proped_children = convert(Vector{T}, filter(c -> !isfalse(c), cn))
            if isempty(proped_children)
                return false_node
            elseif remove_unary && issingle(proped_children)
                return proped_children[1]
            else
                return disjoin(proped_children; reuse=n)
            end
        end
    end
    foldup_aggregate(root, f_con, f_lit, f_a, f_o, Node)
end


import Base.deepcopy

"""
    deepcopy(n::Node, depth::Int64)

Recursively create a copy circuit rooted at `n` to a certain depth `depth`
"""
function deepcopy(n::Node, depth::Int64, old2new::Dict{Node, Node} = Dict{Node, Node}(); cache=true)
    # TODO: can we remove the Dict and use the data field instead?
    if depth == 0 || isliteralgate(n) || isconstantgate(n)
        return n
    elseif cache && haskey(old2new, n)
        return old2new[n]
    else
        cns = map(children(n)) do c
            deepcopy(c, depth - 1, old2new; cache=cache)
        end
        if is⋀gate(n)
            new_n = conjoin(cns)
        else
            @assert is⋁gate(n)
            new_n = disjoin(cns)
        end
        if cache 
            old2new[n] = new_n
        end
        return new_n
    end
end


"""
    condition(root::Node, lit::Lit; callback::Function)::Node

Return the circuit conditioned on given literal constrains
`callback` is called after modifying conjunction node
"""
function condition(root::Node, lit::Lit; callback=noop)::Node
    literals = canonical_literals(root)
    (false_node, ) = canonical_constants(root) # reuse constants when possible
    if isnothing(false_node)
        try
            false_node = compile(typeof(root), false)
        catch e
            false_node = nothing
        end
    end

    if !haskey(literals, -lit)
        root
    elseif haskey(literals, -lit) && !haskey(literals, lit)
        false_node
    else
        f_con(n) = (n, true)
        f_lit(n) = begin
            if variable(n) == lit2var(lit) && literal(n) != lit
                (false_node, false)
            else
                (n, true)
            end
        end
        f_a(n, cv) = begin
            kept = last.(cv)
            new_children = first.(cv)[kept]
            if all(kept)
                (conjoin([new_children...]; reuse=n), true)
            else
                (false_node, false)
            end
        end
        f_o(n, cv) = begin
            kept = last.(cv)
            new_children = first.(cv)[kept]
            if any(kept) && (length(new_children) == 1) && isliteralgate(new_children[1])
                (new_children[1], true)
            elseif any(kept)
                new_n = disjoin([new_children...]; reuse=n)
                callback(new_n, n, kept)
                (new_n, true)
            else
                (false_node, false)
            end
        end
        foldup_aggregate(root, f_con, f_lit, f_a, f_o, Tuple{Union{Nothing,Node}, Bool})[1]
    end
end


import Base.split

"""
    split(root::Node, (or, and)::Tuple{Node, Node}, var::Var; depth=0, sanity_check=true)

Return the circuit after spliting on edge `edge` and variable `var`
"""
function split(root::Node, (or, and)::Tuple{Node, Node}, var::Var; depth=0, sanity_check=true)
    # sanity check
    if sanity_check
        @assert depth >= 0
        @assert is⋁gate(or) && is⋀gate(and) && and in children(or)
        @assert or in or_nodes(root) && and in and_nodes(root)
        literals = canonical_literals(and)
        @assert haskey(literals, var2lit(var)) && haskey(literals, - var2lit(var))
    end

    # split
    new_children1 = map(children(and)) do c
        condition(c, var2lit(var))
    end

    new_children2 = map(children(and)) do c
        condition(c, - var2lit(var))
    end

    new_and1 = deepcopy(conjoin(new_children1), depth; cache=false)
    new_and2 = deepcopy(conjoin(new_children2), depth; cache=false)
    new_or = disjoin([[new_and1, new_and2]; filter(c -> c != and, children(or))])

    replace_node(root, or, new_or), new_or
end


"""
    split_candidates(circuit::Node)::Tuple{Vector{Tuple{Node, Node}}, Dict{Node, BitSet}}

Return the edges and variables which can be splited on
"""
function split_candidates(circuit::Node)::Tuple{Vector{Tuple{Node, Node}}, Dict{Node, BitSet}}
    candidates = Vector{Tuple{Node, Node}}()
    scope = Dict{Node, BitSet}() # cache the literal scopes
    f_con(n) = begin
        scope[n] = BitSet()
        (false, scope[n])
    end
    f_lit(n) = begin
        scope[n] = BitSet(literal(n))
        (false, scope[n])
    end
    f_a(n, cv) = begin
        literals = last.(cv)
        scope[n] = union(literals...)
        variable = union(lit2var.(Int32.(scope[n]))...)
        for v in variable
            if var2lit(v) in scope[n] && - var2lit(v) in scope[n]
                return (true, scope[n])
            end
        end
        (false, scope[n])
    end
    f_o(n, cv) = begin
        literals = last.(cv)
        scope[n] = union(literals...)
        map(zip(first.(cv), children(n))) do (splitable, c)
            if splitable
                push!(candidates, (n, c))
            end
        end
        (any(first.(cv)), scope[n])
    end
    foldup_aggregate(circuit, f_con, f_lit, f_a, f_o, Tuple{Bool, BitSet})

    candidates, scope
end

function clone_candidates(circuit::Node)::Array{Tuple{Node,Node,Node},1}
    candidates = Dict{Node, Vector{Node}}()
    parents = Dict{Node, Vector{Node}}()

    f_con(n) = begin
        false
    end
    f_lit(n) = begin
        false
    end
    f_a(n, cv) = begin
        for c in children(n)
            if !is⋁gate(c)
                continue
            end

            if c in keys(parents)
                push!(parents[c], n)
            else
                parents[c] = [n]
            end
        end
        false
    end
    f_o(n, cv) = begin
        if !(n in keys(parents))
            parents[n] = []
        end
        true
    end

    foldup_aggregate(circuit, f_con, f_lit, f_a, f_o, Bool)

    # Find candidates
    candidates = filter(p->(length(last(p)) == 2), parents) # Set of AND gates shared by exactly 2 OR gates
    return [(k, v[1], v[2]) for (k, v) in candidates]
end

"""
Randomly picking egde and variable from candidates
"""
function random_split(circuit::Node)
    candidates, scope = split_candidates(circuit)
    or, and = rand(candidates)
    lits = collect(Set{Lit}(scope[and]))
    vars =  Var.(intersect(filter(l -> l > 0, lits), - filter(l -> l < 0, lits)))
    var = rand(vars)
    (or, and), var
end

"""
Split step
"""
function split_step(circuit::Node; loss=random_split, depth=0, sanity_check=true)
    edge, var = loss(circuit)
    split(circuit, edge, var; depth=depth, sanity_check=sanity_check)
end

"""
Clone Step
"""
function clone_step(circuit::Node; loss=random_clone, depth=0, sanity_check=true)
    or, and1, and2 = loss(circuit)

    if or == nothing || and1 == nothing || and2 == nothing
        return circuit
    end

    @assert or != nothing "Or is nothing"
    @assert and1 != nothing "And1 is nothing"
    @assert and2 != nothing "And2 is nothing"

    clone(circuit, and1, and2, or; depth=depth)
end

"""
Structure learning manager
"""
function struct_learn(circuit::Node; 
    primitives=[split_step, clone_step], 
    kwargs=Dict(split_step=>(loss=random_split, depth=0),
                clone_step=>(loss=random_clone, depth=0)),
    maxiter=typemax(Int), stop::Function=x->false)

    for iter in 1 : maxiter
        # primiteve_step = rand(primitives)
        primiteve_step = primitives[1]
        # if iter % 2 == 0
        #     println("Doing Clone...")
        #     primiteve_step = primitives[2]
        # end

        kwarg = kwargs[primiteve_step]

        # t0 = Base.time_ns()
        c2, _ = primiteve_step(circuit; kwarg...)
        # t1 = (Base.time_ns() - t0)/(1.0e9)
        # println("Time : $t1")

        if stop(c2)
            return c2
        end
        circuit = c2
    end
    circuit
end


"""
Clone the `or` node and redirect one of its parents to the new copy
"""
function clone(root::Node, and1::Node, and2::Node, or::Node; depth=1)
    # sanity check
    @assert depth >= 1
    @assert is⋀gate(and1) && is⋀gate(and2) && is⋁gate(or)
    @assert or in children(and1) && or in children(and2)
    @assert and1 in and_nodes(root) && and2 in and_nodes(root) && or in or_nodes(root)

    # clone
    new_and2 = nothing
    new_or = deepcopy(or, depth; cache=false)
    new_and2 = conjoin([[new_or]; filter(c -> c != or, children(and2))])

    if or == children(and1)[1]
        new_and2 = conjoin([[new_or]; filter(c -> c != or, children(and2))])
    else
        new_and2 = conjoin([filter(c -> c != or, children(and2))..., new_or])
    end

    replace_node(root, and2, new_and2)
end


import Base.merge
"""
    merge(root::Node, or1::Node, or2::Node)

Merge two circuits.
"""
function merge(root::Node, or1::Node, or2::Node)
    # sanity check
    @assert is⋁gate(or1) && is⋁gate(or2)
    @assert or1 in or_nodes(root) && or2 in or_nodes(root)


    # Simply replace the occurrencce of the larger OR with the smaller OR
    n_or1 = num_nodes(or1)
    n_or2 = num_nodes(or2)

    if n_or1 >= n_or2
        replace_node(root, or1, or2)
    else
        replace_node(root, or2, or1)
    end
end


"""
Replace node `old` with node `new` in circuit `root`
"""
function replace_node(root::Node, old::Node, new::Node; callback::Function=(x, y, z) -> nothing)::Node
    @assert GateType(old) == GateType(new)
    f_con(n) = old == n ? new : n
    f_lit = f_con
    f_a(n, cns) = old == n ? new : conjoin([cns...]; reuse=n)
    f_o(n, cns) = old == n ? new : begin 
            new_n = disjoin([cns...]; reuse=n)
            callback(new_n, n, trues(length(cns)))
            new_n
        end
    foldup_aggregate(root, f_con, f_lit, f_a, f_o, Node)
end


