using Test
using LogicCircuits

module TestNodes

    using Test
    using ..LogicCircuits

    mutable struct TestINode <: Dag
        id::Int
        children::Vector{Dag}
        data
        counter::UInt32
        TestINode(i,c) = new(i,c,nothing,false)
    end

    mutable struct TestLNode <: Dag
        id::Int
        data
        counter::UInt32
        TestLNode(i) = new(i,nothing,false)
    end

    LogicCircuits.NodeType(::Type{<:TestINode}) = Inner()
    LogicCircuits.NodeType(::Type{<:TestLNode}) = Leaf()
    LogicCircuits.children(n::TestINode) = n.children

    @testset "Graphs utils for TestNodes" begin

        l1 = TestLNode(1)
        l2 = TestLNode(2)

        @test !has_children(l1)
        @test num_children(l1) == 0
        @test isleaf(l1)
        @test !isinner(l1)

        i1 = TestINode(1,[l1])
        i2 = TestINode(2,[l2])
        i12 = TestINode(3,[l1,l2])

        @test has_children(i1)
        @test has_children(i12)

        @test num_children(i1) == 1
        @test num_children(i12) == 2

        j1 = TestINode(1,[i1,i12])
        j2 = TestINode(2,[i2])
        j12 = TestINode(3,[i1,i2])

        r = TestINode(5,[j1,j2,j12])

        @test has_children(r)
        @test num_children(r) == 3
        
        reset_counter(r,5)
        @test r.counter == 5
        @test l1.counter == 5
        @test i12.counter == 5

        reset_counter(r)
        @test r.counter == 0
        @test l1.counter == 0
        @test i12.counter == 0

        foreach(r) do n
            n.id += 1
        end
        @test l1.id == 2
        @test l2.id == 3
        @test i12.id == 4
        @test j2.id == 3
        @test r.id == 6
        @test r.counter == 0
        @test l1.counter == 0
        @test i12.counter == 0

        foreach(r, l -> l.id += 1, i -> i.id -= 1)
        @test l1.id == 2+1
        @test l2.id == 3+1
        @test i12.id == 4-1
        @test j2.id == 3-1
        @test r.id == 6-1
        @test r.counter == 0
        @test l1.counter == 0
        @test i12.counter == 0

        @test filter(n -> iseven(n.id), r) == [l2,i2,j2]

        lastvisited = nothing
        foreach(n -> lastvisited=n,r)
        @test lastvisited === r

        lastvisited = nothing
        foreach_down(n -> lastvisited=n,r)
        @test isleaf(lastvisited)

        @test num_nodes(r) == 9
        @test num_edges(r) == 12

        @test isempty(inodes(l1))
        @test leafnodes(l1) == [l1]

        @test issetequal(inodes(r), [i1,i2,i12,j1,j2,j12,r])
        @test issetequal(innernodes(r), [i1,i2,i12,j1,j2,j12,r])
        @test issetequal(leafnodes(r), [l1,l2])
        
        @test tree_num_edges(r) == 14 # unverified

        @test linearize(r)[end] == r
        @test linearize(r)[1] == l1 || linearize(r)[1] == l2
        @test linearize(l2) == [l2]
        @test length(linearize(i12)) == 3

        @test eltype(linearize(r)) == Dag
        @test eltype(linearize(l1)) == TestLNode
        @test eltype(linearize(r, Any)) == Any

        @test left_most_descendent(r) == l1
        @test right_most_descendent(r) == l2

    end    

end

@testset "Node stats tests" begin

    lc = load_logic_circuit(zoo_lc_file("little_4var.circuit"));

    lstats = leaf_stats(lc);
    istats = inode_stats(lc);
    nstats = node_stats(lc);

    @test !(PlainTrueNode in keys(lstats));
    @test !(PlainFalseNode in keys(lstats));
    @test lstats[PlainLiteralNode] == 8;
    
    @test istats[(Plain⋀Node, 2)] == 9;
    @test istats[(Plain⋁Node, 1)] == 10;
    @test istats[(Plain⋁Node, 4)] == 2;
 
    for t in keys(lstats)
        @test lstats[t] == nstats[t]
    end
    for t in keys(istats)
        @test istats[t] == nstats[t]
    end

    @test num_nodes(lc) == 29
    @test num_variables(lc) == 4;
    @test num_edges(lc) == 36;

end