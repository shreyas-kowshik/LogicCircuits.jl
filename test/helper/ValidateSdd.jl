# helper test functions to check for SDD properties holding

function validate(sdd::Sdd)
    for n in sdd
      validate(n)
    end
    #TODO make one of these for structured decomposability
    @assert is_decomposable(sdd)
 end
   
function validate(n::SddNode)
   validate(GateType(n), n)
end

function validate(::⋁, n::SddNode)
   size = num_children(n)
   primes = compile(false)
   for i = 1:size
      element = children(n)[i]
      # has alternating layers
      @test GateType(element) isa ⋀
      for j = i+1:size
         other_element = children(n)[j]
         # is deterministic
         @test is_false(prime(element) & prime(other_element))
         # is compressed
         @test sub(element) !== sub(other_element)
      end
      primes = primes | prime(element)
   end
   # is exhaustive
   @test primes === compile(true)
   # cannot be trimmed to the sub
   @test size >= 1
   # cannot be trimmed to the prime
   if size == 2
      e1 = children(n)[1]
      e2 = children(n)[2]
      has_false_sub = (is_false(sub(e1)) || is_false(sub(e2)))
      has_true_sub = (is_true(sub(e1)) || is_true(sub(e2)))
      @test !(has_false_sub && has_true_sub)
   end
end

function validate(::⋀, n::SddNode)
   @test num_children(n) == 2
   @test !(GateType(prime(n)) isa ⋀)
   @test !(GateType(sub(n)) isa ⋀)
   # has no false prime
   @test !is_false(prime(n))
end

function validate(::LeafGate, ::SddNode)
   # no op
end