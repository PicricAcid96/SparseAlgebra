import Base.show
import Base.*
import QuantumLab
export BCSRSpM

#"Sparse matrix type in block compressed sparse row format"
type BCSRSpM
	val::Array{Array{Float64,2},1}
	col::Array{Int,1}
	rowptr::Array{Int,1}
	rowpattern::Array{Int,1}
	colpattern::Array{Int,1}
	function BCSRSpM(M::Array{Float64,2},rowpattern::Array{Int,1},colpattern::Array{Int,1})
	  (checkPattern(M,rowpattern,1) && checkPattern(M,colpattern,2)) || error("Hey idiot your pattern doesn't match the matrix ᕦ(ò_óˇ)ᕤ")
      val,col,rowptr = computeBCSRSpMFields(M,rowpattern,colpattern)
      new(val,col,rowptr,rowpattern,colpattern)
    end
end

#"Alternative constructor using shells"
function BCSRSpM(M::Array{Float64,2},basis::Array{QuantumLab.ShellModule.Shell,1}) 
	BCSRSpM(M::Array{Float64,2},computePatternFromBasis(basis::Array{QuantumLab.ShellModule.Shell,1}),computePatternFromBasis(basis::Array{QuantumLab.ShellModule.Shell,1}))
end

#"Alternative constructor using increased block size format"
function BCSRSpM(M::Array{Float64,2},basis::Array{QuantumLab.ShellModule.Shell,1},b::Bool)
	p = computeIncreasedBlockSizePattern(computePatternFromBasis(basis::Array{QuantumLab.ShellModule.Shell,1}))
	pattern::Array{Int,1} = []
	for i = 1:length(p)
		push!(pattern,p[i][1],p[i][2])
	end
	BCSRSpM(M::Array{Float64,2},pattern,pattern)
end

#"Sparse matrix type in block compressed sparse row format for symmetric matrices"
type symBCSRSpM
	val::Array{Union{Array{Float64,2},LowerTriangular{Float64,Array{Float64,2}}},1}
	col::Array{Int,1}
	rowptr::Array{Int,1}
	pattern::Array{Int,1}
	function symBCSRSpM(M::Array{Float64,2},pattern::Array{Int,1})
		checkPattern(M,pattern,1) || error("In case of error flip table ╯°□°）╯︵ ┻━┻")
		val,col,rowptr = convertSMtoSpMBCSR(M,pattern,true)
		new(val,col,rowptr,pattern)
	end
end

#"Alternative constructor using shells"
function symBCSRSpM(M::Array{Float64,2},basis::Array{QuantumLab.ShellModule.Shell,1})
	symBCSRSpM(M::Array{Float64,2},computePatternFromBasis(basis::Array{QuantumLab.ShellModule.Shell,1}))
end

#"Show BCSRSpM sparse matrix with * for every block norm = 0."
function show(io::IO,SpM::BCSRSpM)
	M = fillSpMWithChar(SpM,*)
	display(M)
end

#"Show symBCSRSpM sparse matrix with * for every block norm = 0."
function show(io::IO,SpM::symBCSRSpM)
	M = fillSpMWithChar(SpM,*)
	display(M)
end

#"Function checks pattern for 1. first element 1, 2. last element dimension of matrix, 3. gaplessness"
function checkPattern(M::Array{Float64,2},pattern::Array{Int,1},dim::Int)
	check::Bool = true
	if pattern[1] != 1 return false end
	if pattern[end] != size(M,dim) return false end
	s::Int32        = length(pattern)/2-1
	for i = 1:s
		if pattern[2*(i-1)+2]+1 != pattern[2*(i-1)+3] return false end
	end

	return check
end

#"Define multiplication for BCSRSpM sparse matrix with vector"
*(SpM::BCSRSpM,vec::Array{Float64,1}) = multiplySpMV(SpM,vec)

#"Define multiplication for BCSRSpM sparse matrix with dense matrix"
*(SpM::BCSRSpM,M::Array{Float64,2}) = multiplySpMM(SpM,M)

#"Define multiplication for BCSRSpM sparse matrix with BCSRSpM sparse matrix"
*(SpM1::BCSRSpM,SpM2::BCSRSpM) = multiplySpMSpM(SpM1,SpM2)

#"Function generates pattern from shells"
function computePatternFromBasis(basis::Array{QuantumLab.ShellModule.Shell,1})
    nbf     = []
    pattern = []
    sum     = 0
    [push!(nbf,QuantumLab.ShellModule.nbf(basis[i])) for i in 1:length(basis)]
    δ = [nbf[i+1]-nbf[i] for i in 1:length(nbf)-1]
    δ = vcat(0,δ)
    [if(δ[i]<0) δ[i] = 0. end for i in 1:length(nbf)]
    for i = 1:length(basis)
        sum += 1
		push!(pattern,sum)
        push!(pattern,sum+nbf[i]-1)
        sum = pattern[end]
    end
    return Array{Int64,1}(pattern)
end

#"Function generates tupel pattern from shells"
function computeTupelPatternFromBasis(basis::Array{QuantumLab.ShellModule.Shell,1})
	nbf = []
	pattern = []
	sum = 1
	[push!(nbf,QuantumLab.ShellModule.nbf(basis[i])) for i in 1:length(basis)]
	δ = [nbf[i+1]-nbf[i] for i in 1:length(nbf)-1]
	δ = vcat(0,δ)
	sum = 0
	return δ
	pattern = []
	for i = 1:length(basis)
		sum += 1
		push!(pattern,(sum,sum+nbf[i]-1))
		sum = pattern[end][2]
	end
	
	return pattern
end

#"Function generates pattern with min. block size 100"
function computeIncreasedBlockSizePattern(pattern::Array{Int64,1})
	nbf = []
	[push!(nbf,QuantumLab.ShellModule.nbf(basis[i])) for i in 1:length(basis)]
	
	sum1 = 0
	sum2 = 0	 
	pattern2 = []
	for i = 1:length(nbf)
		sum2 += nbf[i]
		if sum2 > 100 
			push!(pattern2,(sum1+1,sum1+sum2))
			sum1 += sum2
			sum2 = 0
		elseif i == length(nbf)
			push!(pattern2,(sum1+1,sum1+sum2))
		end
	end
	return pattern2
end	

#"Function purges BCSR sparse matrix where blocks satisfy norm(block) < threshold"
function purgeSparseMatrix(SpM::BCSRSpM)
    len = length(SpM.rowptr)-1
    del::Array{Int} = []
    delrow::Array{Int} = [] 
    
    for i = 1:len
        a,b = computeDifferenceRowptr(i,SpM.rowptr)
        for j = a:b
            if norm(SpM.val[j]) < 1e-5
                push!(del,j)
                push!(delrow,i)
            end
        end
    end

    deleteat!(SpM.val,del)
    deleteat!(SpM.col,del)
    for i = 1:length(delrow)
        SpM.rowptr[(delrow[i]+1):end] -= 1
    end
    return SpM
end

#"TODO"
function test(M::Array{Float64,2},basis)
	if issymmetric(M)
		pattern = computePatternFromBasis(basis::Array{QuantumLab.ShellModule.Shell,1})
		SpM	= symBCSRSpM([],[],[0],[1,2,3])
	else 
		rowpattern
		SpM = BCSRSpM([],[],[0],rowpattern,colpattern)
	end
	return typeof(SpM)
end

#"TODO for loop kuerzer schreiben"
#"Converts a LowerTriangular to the corresponding symmetric matrix"
function symmetrizeLowerTriangular(lt::LowerTriangular{Float64,Array{Float64,2}})
	M::Array{Float64,2} = Array{Float64,2}(lt)
	n					= size(M,1)
	N					= zeros(n,n)
	for i = 1:n, j = 1:n
		N[i,j] = M[i,j]
		if i == j N[i,j] = 0. end
	end

	return M+N'
end

#"Computes the dimension of block to be stored"
function computeBlock(M::Array{Float64,2},rowpattern::Array{Int,1},colpattern::Array{Int,1},i::Int,j::Int)
	block = M[rowpattern[2*(i-1)+1]:(rowpattern[2*(i-1)+2]),colpattern[2*(j-1)+1]:(colpattern[2*(j-1)+2])]
	return block
end 

#"Function computes val,col,rowptr for a matrix with given pattern: BCSRSpM"
function computeBCSRSpMFields(M::Array{Float64,2},rowpattern::Array{Int,1},colpattern::Array{Int,1})
	s1::Int32		= length(rowpattern)/2 
	s2::Int32		= length(colpattern)/2
	nnzb			= 0
	val				= []
	col				= []
	rowptr			= [0]

	for i = 1:s1
		for j = 1:s2
			block = computeBlock(M,rowpattern,colpattern,i,j)
			if norm(block) != 0.
				push!(val, block)
				push!(col,j)
				nnzb += 1
			end
		end
		push!(rowptr,nnzb)
	end

	return val,col,rowptr
end

#"Function computes val,col,rowptr for a matrix with given pattern: symBCSRSpM"
function convertSMtoSpMBCSR(M::Array{Float64,2},pattern::Array{Int,1},tri::Bool)
	
	s::Int32		= length(pattern)/2
	nnzb			= 0
	val				= []
	col				= []
	rowptr			= [0]

	for i = 1:s
		for j = 1:s
			if j <= i
				block = computeBlock(M,pattern,pattern,i,j)
				if tri == true && i == j
					block = LowerTriangular(block)
				end
				if norm(block) != 0.
					push!(val,block)
					push!(col,j)
					nnzb += 1
				end
			end
		end
		push!(rowptr,nnzb)
	end
		
	return val,col,rowptr
end

function convertSpMToMBCSR(SpM::BCSRSpM)
	M = fillSpMWithChar(SpM,0.)
	return M
end

function convertSpMToSMBCSR(SpM::symBCSRSpM)
	M = fillSpMWithChar(SpM,0.)
	return M
end

function computeSegmentForBlock(SpM::Union{BCSRSpM,symBCSRSpM},i,j)
	if isa(SpM,BCSRSpM)
		rowpattern = SpM.rowpattern
		colpattern = SpM.colpattern
	elseif isa(SpM,symBCSRSpM)
		rowpattern = SpM.pattern
		colpattern = SpM.pattern
	end
	a = rowpattern[2*(i-1)+1]
	b = rowpattern[2*(i-1)+2]
	c = colpattern[2*(SpM.col[j]-1)+1]
	d = colpattern[2*(SpM.col[j]-1)+2]

	return a,b,c,d
end
	
function fillSpMWithChar(SpM::Union{BCSRSpM,symBCSRSpM},a::Any)
	if isa(SpM,BCSRSpM)
		dim1::Int32		= SpM.rowpattern[end]
		dim2::Int32		= SpM.colpattern[end]
	elseif isa(SpM,symBCSRSpM)
		dim1			= SpM.pattern[end]
		dim2			= SpM.pattern[end]
	end
		
	M::Array{Any,2}		= fill(a,dim1,dim2)
	len::Int32			= length(SpM.rowptr)-1
	δ::Array{Int,1}		= [SpM.rowptr[i+1]-SpM.rowptr[i] for i in 1:len]

	j = 1
	for i = 1:len
		z = 0
		while z < δ[i]
			a,b,c,d = computeSegmentForBlock(SpM,i,j)
			el = SpM.val[j]
			if isa(SpM,BCSRSpM)
				M[a:b,c:d] = el
			elseif isa(SpM,symBCSRSpM)
				if a == c && b == d && typeof(SpM.val[j]) == LowerTriangular{Float64,Array{Float64,2}} 
					el = symmetrizeLowerTriangular(el)
				end
				M[a:b,c:d] = el
				M[c:d,a:b] = el'
			end
			j += 1
			z += 1
		end
	end
		
	return M
end

function computeDifferenceRowptr(i::Int,rowptr)
    a = rowptr[i]+1
    b = rowptr[i+1]
	return a,b
end

#"Apply pattern of sparse matrix to a vector"
function convertVToBV(vec::Array{Float64,1},SpM::BCSRSpM)
	len::Int64							= Int64(round(length(SpM.colpattern)/2,0))
	blockvec::Array{Array{Float64,1}}	= []
	for i = 1:len
		push!(blockvec,vec[SpM.colpattern[2*(i-1)+1]:SpM.colpattern[2*(i-1)+2]])
	end
		
	return blockvec
end

#"Function multiplies BCSR sparse matrix with vector"
function multiplySpMV(SpM::BCSRSpM,vec::Array{Float64,1})
	len						= length(SpM.rowptr)-1
	res::Array{Float64,1}	= zeros(length(vec)) 
	blockVec	= convertVToBV(vec,SpM)
	
	for i = 1:len
		a,b = computeDifferenceRowptr(i,SpM.rowptr)
		for j = a:b
			res[SpM.colpattern[2*(i-1)+1]:SpM.colpattern[2*(i-1)+2]] += SpM.val[j] * blockVec[SpM.col[j]]
		end
	end
	
	return res
end

#"Function computes the row (analog to BCSRSpM field col) from rowptr"
function computeRowFromRowptr(SpM::BCSRSpM)
	len::Int32          = length(SpM.rowptr)-1
	δ::Array{Int,1}     = [SpM.rowptr[i+1]-SpM.rowptr[i] for i in 1:len]
	row::Array{Int,1}	= []
	for i = 1:length(δ), j = 1:δ[i]
		push!(row,i)
	end
	return row
end

#"TODO change pattern to tupel pattern for entire code maybe..."
#"Generate tupel pattern from pattern"
function computeTupelPatternFromPattern(pattern::Array{Int,1})
	len								= Int64(round(length(pattern)/2,0))
	a::Array{Tuple{Int64,Int64},1}	= []
	[push!(a,(pattern[2*(i-1)+1],pattern[2*(i-1)+2])) for i in 1:len]
	return a
end

#"Function multiplies BCSR sparse matrix with dense matrix"
function multiplySpMM(SpM::BCSRSpM,M::Array{Float64,2})
	if SpM.colpattern[end] != size(M,1) error("Dimensions do not match ԅ(≖‿≖ԅ)") end

	s = size(M,2)
	Mpattern = SpM.rowpattern[1:findlast(SpM.rowpattern,s)]
	a = computeTupelPatternFromPattern(SpM.colpattern)
	b = computeTupelPatternFromPattern(Mpattern)	
	res = zeros(SpM.rowpattern[end],size(M,2))	
	row = computeRowFromRowptr(SpM)	
	
	for i = 1:length(SpM.val)
		for j = 1:length(b)
			res[a[row[i]][1]:a[row[i]][2],b[j][1]:b[j][2]] += SpM.val[i]*M[a[SpM.col[i]][1]:a[SpM.col[i]][2],b[j][1]:b[j][2]]
		end
	end
	return res
end

#"Function multiplies BCSR sparse matrix with BCSR sparse matrix"
function multiplySpMSpM(SpM1::BCSRSpM,SpM2::BCSRSpM)
	if SpM1.colpattern != SpM2.rowpattern error("Patterns do not match (ﾉ◕ヮ◕)ﾉ*:・ﾟ✧") end

	res = zeros(SpM1.rowpattern[end],SpM2.colpattern[end])
	row1 = computeRowFromRowptr(SpM1)
	row2 = computeRowFromRowptr(SpM2)

	a = computeTupelPatternFromPattern(SpM1.colpattern)
	b = computeTupelPatternFromPattern(SpM2.rowpattern)

	for i = 1:length(SpM1.val), j = 1:length(SpM2.val)
			if SpM1.col[i] == row2[j]
				res[a[row1[i]][1]:a[row1[i]][2],b[SpM2.col[j]][1]:b[SpM2.col[j]][2]] += SpM1.val[i]*SpM2.val[j]
			end
	end
	return res
end

