# -----------------------------------------------------------
#
# Using boundary terms and integration (summation) by parts
# to construct more accurate derivative matrices for time
# evolution using Lax-Friedricks-type fluxes
#
# All derivatives are computed here in pos basis first
# Then conjugated into hier basis
#
# -----------------------------------------------------------


# -----------------------------------------------------
# Generates the coefficients for a traveling wave 
# A cos(\vec{k} \cdot \vec{x} + \phi), \vec{k} = 2 \pi \vec{m}
# with sparse interpolation of type (k,n) 
# using periodic boundary conditions in D-dimensionss
# -----------------------------------------------------

function cos_coeffs(k::Int, n::Int, m::Array{Int,1};
					scheme="sparse", phase = 0.0, A = 1.0)
	D = length(m)
	wavenumber = 2*pi*m

	# Begin with writing cos(\sum_i k_i x_i) as a sum of products
	# of sines/cosines of individual k_j x_j
	sines   = [i==1?x->sin(wavenumber[i]*x[1]+phase):x->sin(wavenumber[i]*x[1]) for i in 1:D]
	cosines = [i==1?x->cos(wavenumber[i]*x[1]+phase):x->cos(wavenumber[i]*x[1]) for i in 1:D]

	sine_dicts   = [coeffs_DG(1, k, n, sines[i]) for i in 1:D]
	cosine_dicts = [coeffs_DG(1, k, n, cosines[i]) for i in 1:D]

	ansVect = zeros(get_size(D, k, n; scheme=scheme))

	for SCs in CartesianRange(ntuple(q->2, D))
		num_sines = sum([SCs[i]-1 for i in 1:D])
		if num_sines % 2 == 1
			continue 
		end
		sign = num_sines%4==0?1:-1
		# may want to add an if-statement for if any n[i] == 0

		coeff_array = [SCs[i]==1?cosine_dicts[i]:sine_dicts[i] for i in 1:D]
		productDict = tensor_construct(D, k, n, coeff_array; scheme=scheme)
		productVect = D2V(D, k, n, productDict; scheme=scheme)

		ansVect += sign * productVect
	end

	return A * ansVect
end

# -----------------------------------------------------
# The same as above, but using sin
# -----------------------------------------------------

function sin_coeffs(k::Int, n::Int, m::Array{Int,1};
					scheme="sparse", phase=0.0, A=1.0)
	return cos_coeffs(k, n, m; scheme=scheme, phase=phase-pi/2, A=A)
end

# -----------------------------------------------------
# Returns the data for a traveling wave 
# using the above methods
# -----------------------------------------------------

function traveling_wave(k::Int, n::Int, m::Array{Int,1};
						scheme="sparse", phase=0.0, A=1.0)
	wavenumber = 2*pi*m
	frequency = sqrt(vecdot(wavenumber,wavenumber))
	u0 = x -> A * cos(vecdot(wavenumber,x) + phase)
	v0 = x -> A * frequency * sin(vecdot(k,x) + phase)
	u0_coeffs = cos_coeffs(k, n, m; scheme=scheme, phase=phase, A=A) 
	v0_coeffs = sin_coeffs(k, n, m; scheme=scheme, phase=phase, A=A*frequency) 

	return (u0_coeffs, v0_coeffs, u0, v0)
end

# -----------------------------------------------------
# Evolves a traveling wave using the above methods
# between time0 and time1
# using an ODE solver of type 'order' (default 45)
# -----------------------------------------------------
function traveling_wave_solver(k::Int, n::Int, m::Array{Int,1}, time0::Real, time1::Real; 
								scheme="sparse", phase=0.0, A=1.0, order="45", kwargs...)
	D = length(m)
	f0coeffs, v0coeffs = traveling_wave(k, n, m; scheme=scheme, phase=phase, A=A)
	laplac = laplacian_matrix(D, k, n; scheme=scheme)
	
	RHS, y0 = wave_data(laplac, f0coeffs, v0coeffs)

	if order == "78"
		soln=ode78((t,x)->*(RHS,x), y0, [time0,time1]; kwargs...)
	elseif order == "45"
		soln=ode45((t,x)->*(RHS,x), y0, [time0,time1]; kwargs...)
	else
		throw(ArgumentError)
	end
	return soln
end
