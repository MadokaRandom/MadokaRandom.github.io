#!/usr/bin/env julia

using LinearAlgebra
using Arpack
using Formatting
using Plots

# Some functions
function get_density(fn::Vector{Float64}, ψ::Matrix{Float64}, Δx::Float64) ::Vector{Float64}
    # fn 是长度为 nlevel 的向量，表示电子的占据数函数
    # ψ 是一个 ngrid x nlevel 的矩阵

    # 首先来归一化波函数
    norms = sum(ψ.^2, dims=1) * Δx
    ψ ./= sqrt.(norms)

    # 求电子密度函数
    ρ = sum(ψ.^2 .* fn', dims=2)
    ρ = dropdims(ρ; dims=2)

    return ρ
end

function get_hartree(ρ::Vector{Float64}, x::Vector{Float64}; eps=1e-1) ::Tuple{Float64, Vector{Float64}}
    Δx = x[2] - x[1]
    energy = sum((ρ * ρ' .* Δx^2) ./ sqrt.((x' .- x).^2 .+ eps)) / 2
    potential = collect(Iterators.flatten((sum(ρ' .* Δx ./ sqrt.((x' .- x).^2 .+ eps), dims=2))))
    return (energy, potential)
end

function get_exchange(ρ::Vector{Float64}, Δx::Float64) ::Tuple{Float64, Vector{Float64}}
    energy = -3.0/4.0 * cbrt(3.0/π) * sum(ρ.^(4.0/3.0)) * Δx
    potential = -cbrt(3.0/π) .* (cbrt.(ρ))
    return (energy, potential)
end

function get_hamiltonian(x::Vector{Float64}, ρ::Vector{Float64},
                         v_ext::Vector{Float64}) ::Matrix{Float64}
    Δx = x[2] - x[1]
    ex_energy, ex_potential = get_exchange(ρ, Δx)
    ha_energy, ha_potential = get_hartree(ρ, x)
    ∇² = Tridiagonal(ones(ngrid-1), -2*ones(ngrid), ones(ngrid-1)) ./ (Δx^2)

    # Hamiltonian
    H = -∇²./2 + Diagonal(ex_potential .+ ha_potential .+ v_ext)

    return H
end

if abspath(PROGRAM_FILE) == @__FILE__
    ngrid = 200
    nlevel = 20
    nelect = 17

    x = collect(LinRange(-5, 5, ngrid))
    Δx = x[2] - x[1]
    ∇² = Tridiagonal(ones(ngrid-1), -2*ones(ngrid), ones(ngrid-1)) ./ (Δx^2)

    # V_ext
    V_empty = zeros(ngrid)
    V_well = fill(1e10, ngrid); @. V_well[-2 <= x <= 2] = 0;
    V_harm = x.^2

    # construct fn
    fn = zeros(nlevel)
    fn[1:(nelect÷2)] .= 2
    if 1 == nelect % 2
        fn[nelect÷2+1] = 1
    end

    max_iter = 1000
    E_threshold = 1E-5

    log0 = Dict("E" => [Inf], "ΔE" => [Inf])  # Use `log0` instead of `log` to avoid confict

    # 使用自由电子的波函数做为初始猜测的电子波函数，可以加速收敛
    E, ψ = eigs(-∇²./2.0, nev=nlevel, which=:LM, sigma=0)
    ρ = get_density(fn, ψ, Δx)

    for i in 1:max_iter
        H = get_hamiltonian(x, ρ, V_harm)

        E0, ψ0 = eigs(H, nev=nlevel, which=:LM, sigma=0)
        E .= E0
        ψ .= ψ0

        E_tot = sum(E .* fn)  # 求占据态电子能量之和
        ΔE = E_tot - log0["E"][end]
        push!(log0["E"], E_tot)
        push!(log0["ΔE"], ΔE)
        printfmtln("step: {:5d} E: {:10.4f} ΔE {:14.10f}", i, log0["E"][end], log0["ΔE"][end])

        # 判断基能量是否收敛
        if abs(ΔE) < E_threshold
            println("converged!")
            break
        end

        # 更新电子密度
        ρ .= get_density(fn, ψ, Δx)
    end

    p = plot(x, ψ[:, 1:5], label=sprintf1.("%.3f", E[1:5]'), title="ψ")
end
