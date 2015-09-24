
##############################################################################
## 
## Utils
##
##############################################################################

macro isok(A)
    :($A ==  Int32(1) || throw(CHOLMODException("")))
end

# Update B as A'
function transpose_unsym_!{Tv<: VTypes}(A::Sparse{Tv}, values::Integer, B::Sparse{Tv})
    @isok ccall((@cholmod_name("transpose_unsym", SuiteSparse_long),:libcholmod),
        Cint,
            (Ptr{C_Sparse{Tv}}, Cint, Ptr{SuiteSparse_long}, Ptr{SuiteSparse_long}, Csize_t, Ptr{C_Sparse{Tv}}, Ptr{UInt8}),   
            A.p, values, C_NULL, C_NULL, 0, B.p, common())
    return B
end

# Update B as Sparse(A)
function Sparse!{Tv<:VTypes,Ti<:ITypes}(A::SparseMatrixCSC{Tv,Ti}, B::Sparse{Tv})
    s = unsafe_load(B.p)
    for i = 1:length(A.colptr)
        unsafe_store!(s.p, A.colptr[i] - 1, i)
    end
    for i = 1:length(A.rowval)
        unsafe_store!(s.i, A.rowval[i] - 1, i)
    end
    unsafe_copy!(s.x, pointer(A.nzval), length(A.nzval))
    @isok check_sparse(B)
    return B
end

##############################################################################
## 
## Dogleg : solve J'J \ J'y
##
##############################################################################

type SparseDogleg{Tx} <: AbstractSolver
    x::Tx
    J::Sparse{Float64}
    Jt::Sparse{Float64}
    F::Factor{Float64}
    cm::Array{UInt8, 1}
end

function allocate(nls::SparseLeastSquaresProblem,
    ::Type{Val{:dogleg}}, ::Type{Val{:factorization}})
    sparseJ = Sparse(nls.J)
    sparseJt = transpose_(sparseJ, 2)
    cm = defaults(common()) 
    set_print_level(cm, 0)
    unsafe_store!(common_final_ll, 1)
    F = analyze(sparseJt, cm)
    return SparseDogleg(_zeros(nls.x), sparseJ, sparseJt, F, cm)
end

function solve!{T <: SparseLeastSquaresProblem , Tmethod <: Dogleg, Tsolve <: SparseDogleg}(
    anls::LeastSquaresProblemAllocated{T, Tmethod, Tsolve})
    J, y = anls.nls.J, anls.nls.y
    x, sparseJ, sparseJt, F, cm = anls.solve.x,anls.solve.J, anls.solve.Jt, anls.solve.F, anls.solve.cm
    Sparse!(J, sparseJ)
    transpose_unsym_!(sparseJ, 2, sparseJt)
    factorize_p!(sparseJt, 0, F, cm)
    Ac_mul_B!(x, J, y)
    # !! there is a memory allocation here
    copy!(anls.method.δgn, F \ x)
    return 1
end