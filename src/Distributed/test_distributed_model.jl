using Test
using MPI
using Oceananigans

using Oceananigans.BoundaryConditions: fill_halo_regions!

MPI.Initialized() || MPI.Init()
comm = MPI.COMM_WORLD

# Right now just testing with 4 ranks!
mpi_ranks = MPI.Comm_size(comm)
@assert mpi_ranks == 4

#####
##### Multi architectures and rank connectivity
#####

function run_triply_periodic_rank_connectivity_tests_with_411_ranks()
    topo = (Periodic, Periodic, Periodic)
    full_grid = RegularCartesianGrid(topology=topo, size=(8, 8, 8), extent=(1, 2, 3))
    arch = MultiCPU(grid=full_grid, ranks=(4, 1, 1))

    my_rank = MPI.Comm_rank(MPI.COMM_WORLD)
    @test my_rank == index2rank(arch.my_index..., arch.ranks...)

    connectivity = arch.connectivity

    # No communication in y and z.
    @test isnothing(connectivity.south)
    @test isnothing(connectivity.north)
    @test isnothing(connectivity.top)
    @test isnothing(connectivity.bottom)

    if my_rank == 0
        @test connectivity.east == 1
        @test connectivity.west == 3
    elseif my_rank == 1
        @test connectivity.east == 2
        @test connectivity.west == 0
    elseif my_rank == 2
        @test connectivity.east == 3
        @test connectivity.west == 1
    elseif my_rank == 3
        @test connectivity.east == 0
        @test connectivity.west == 2
    end

    return nothing
end

function run_triply_periodic_rank_connectivity_tests_with_141_ranks()
    topo = (Periodic, Periodic, Periodic)
    full_grid = RegularCartesianGrid(topology=topo, size=(8, 8, 8), extent=(1, 2, 3))
    arch = MultiCPU(grid=full_grid, ranks=(1, 4, 1))

    my_rank = MPI.Comm_rank(MPI.COMM_WORLD)
    @test my_rank == index2rank(arch.my_index..., arch.ranks...)

    connectivity = arch.connectivity

    # No communication in x and z.
    @test isnothing(connectivity.east)
    @test isnothing(connectivity.west)
    @test isnothing(connectivity.top)
    @test isnothing(connectivity.bottom)

    if my_rank == 0
        @test connectivity.north == 1
        @test connectivity.south == 3
    elseif my_rank == 1
        @test connectivity.north == 2
        @test connectivity.south == 0
    elseif my_rank == 2
        @test connectivity.north == 3
        @test connectivity.south == 1
    elseif my_rank == 3
        @test connectivity.north == 0
        @test connectivity.south == 2
    end

    return nothing
end

function run_triply_periodic_rank_connectivity_tests_with_114_ranks()
    topo = (Periodic, Periodic, Periodic)
    full_grid = RegularCartesianGrid(topology=topo, size=(8, 8, 8), extent=(1, 2, 3))
    arch = MultiCPU(grid=full_grid, ranks=(1, 1, 4))

    my_rank = MPI.Comm_rank(MPI.COMM_WORLD)
    @test my_rank == index2rank(arch.my_index..., arch.ranks...)

    connectivity = arch.connectivity

    # No communication in x and y.
    @test isnothing(connectivity.east)
    @test isnothing(connectivity.west)
    @test isnothing(connectivity.north)
    @test isnothing(connectivity.south)

    if my_rank == 0
        @test connectivity.top == 1
        @test connectivity.bottom == 3
    elseif my_rank == 1
        @test connectivity.top == 2
        @test connectivity.bottom == 0
    elseif my_rank == 2
        @test connectivity.top == 3
        @test connectivity.bottom == 1
    elseif my_rank == 3
        @test connectivity.top == 0
        @test connectivity.bottom == 2
    end

    return nothing
end

#####
##### Local grids for distributed models
#####

function run_triply_periodic_local_grid_tests_with_411_ranks()
    topo = (Periodic, Periodic, Periodic)
    full_grid = RegularCartesianGrid(topology=topo, size=(8, 8, 8), extent=(1, 2, 3))
    arch = MultiCPU(grid=full_grid, ranks=(4, 1, 1))
    dm = DistributedModel(architecture=arch, grid=full_grid)

    my_rank = MPI.Comm_rank(MPI.COMM_WORLD)

    model = dm.model
    nx, ny, nz = size(model.grid)
    @test model.grid.xF[1] == 0.25*my_rank
    @test model.grid.xF[nx+1] == 0.25*(my_rank+1)
    @test model.grid.yF[1] == 0
    @test model.grid.yF[ny+1] == 2
    @test model.grid.zF[1] == -3
    @test model.grid.zF[nz+1] == 0

    return nothing
end

function run_triply_periodic_local_grid_tests_with_141_ranks()
    topo = (Periodic, Periodic, Periodic)
    full_grid = RegularCartesianGrid(topology=topo, size=(8, 8, 8), extent=(1, 2, 3))
    arch = MultiCPU(grid=full_grid, ranks=(1, 4, 1))
    dm = DistributedModel(architecture=arch, grid=full_grid)

    my_rank = MPI.Comm_rank(MPI.COMM_WORLD)

    model = dm.model
    nx, ny, nz = size(model.grid)
    @test model.grid.xF[1] == 0
    @test model.grid.xF[nx+1] == 1
    @test model.grid.yF[1] == 0.5*my_rank
    @test model.grid.yF[ny+1] == 0.5*(my_rank+1)
    @test model.grid.zF[1] == -3
    @test model.grid.zF[nz+1] == 0

    return nothing
end

function run_triply_periodic_local_grid_tests_with_114_ranks()
    topo = (Periodic, Periodic, Periodic)
    full_grid = RegularCartesianGrid(topology=topo, size=(8, 8, 8), extent=(1, 2, 3))
    arch = MultiCPU(grid=full_grid, ranks=(1, 1, 4))
    dm = DistributedModel(architecture=arch, grid=full_grid)

    my_rank = MPI.Comm_rank(MPI.COMM_WORLD)

    model = dm.model
    nx, ny, nz = size(model.grid)
    @test model.grid.xF[1] == 0
    @test model.grid.xF[nx+1] == 1
    @test model.grid.yF[1] == 0
    @test model.grid.yF[ny+1] == 2
    @test model.grid.zF[1] == -3 + 0.75*my_rank
    @test model.grid.zF[nz+1] == -3 + 0.75*(my_rank+1)

    return nothing
end

#####
#####
#####

function run_triply_periodic_bc_injection_tests_with_411_ranks()
    topo = (Periodic, Periodic, Periodic)
    full_grid = RegularCartesianGrid(topology=topo, size=(8, 8, 8), extent=(1, 2, 3))
    arch = MultiCPU(grid=full_grid, ranks=(4, 1, 1))
    dm = DistributedModel(architecture=arch, grid=full_grid)

    for field in fields(dm.model)
        @test field.boundary_conditions.east isa HaloCommunicationBC
        @test field.boundary_conditions.west isa HaloCommunicationBC
        @test !isa(field.boundary_conditions.north, HaloCommunicationBC)
        @test !isa(field.boundary_conditions.south, HaloCommunicationBC)
        @test !isa(field.boundary_conditions.top, HaloCommunicationBC)
        @test !isa(field.boundary_conditions.bottom, HaloCommunicationBC)
    end
end

function run_triply_periodic_bc_injection_tests_with_141_ranks()
    topo = (Periodic, Periodic, Periodic)
    full_grid = RegularCartesianGrid(topology=topo, size=(8, 8, 8), extent=(1, 2, 3))
    arch = MultiCPU(grid=full_grid, ranks=(1, 4, 1))
    dm = DistributedModel(architecture=arch, grid=full_grid)

    for field in fields(dm.model)
        @test !isa(field.boundary_conditions.east, HaloCommunicationBC)
        @test !isa(field.boundary_conditions.west, HaloCommunicationBC)
        @test field.boundary_conditions.north isa HaloCommunicationBC
        @test field.boundary_conditions.south isa HaloCommunicationBC
        @test !isa(field.boundary_conditions.top, HaloCommunicationBC)
        @test !isa(field.boundary_conditions.bottom, HaloCommunicationBC)
    end
end

function run_triply_periodic_bc_injection_tests_with_114_ranks()
    topo = (Periodic, Periodic, Periodic)
    full_grid = RegularCartesianGrid(topology=topo, size=(8, 8, 8), extent=(1, 2, 3))
    arch = MultiCPU(grid=full_grid, ranks=(1, 1, 4))
    dm = DistributedModel(architecture=arch, grid=full_grid)

    for field in fields(dm.model)
        @test !isa(field.boundary_conditions.east, HaloCommunicationBC)
        @test !isa(field.boundary_conditions.west, HaloCommunicationBC)
        @test !isa(field.boundary_conditions.north, HaloCommunicationBC)
        @test !isa(field.boundary_conditions.south, HaloCommunicationBC)
        @test field.boundary_conditions.top isa HaloCommunicationBC
        @test field.boundary_conditions.bottom isa HaloCommunicationBC
    end
end

#####
##### Halo communication
#####

function run_triply_periodic_halo_communication_tests_with_411_ranks()
    topo = (Periodic, Periodic, Periodic)
    full_grid = RegularCartesianGrid(topology=topo, size=(8, 8, 1), extent=(1, 2, 3))
    arch = MultiCPU(grid=full_grid, ranks=(4, 1, 1))
    dm = DistributedModel(architecture=arch, grid=full_grid)

    for field in fields(dm.model)
        set!(field, arch.my_rank)
        fill_halo_regions!(field, arch)

        @test all(east_halo(field) .== arch.connectivity.east)
        @test all(west_halo(field) .== arch.connectivity.west)
    end

    return nothing
end

#####
##### Run tests!
#####

@testset "Distributed MPI Oceananigans" begin
    @info "Testing distributed MPI Oceananigans..."

    @testset "Multi architectures rank connectivity" begin
        @info "  Testing multi architecture rank connectivity..."
        run_triply_periodic_rank_connectivity_tests_with_411_ranks()
        run_triply_periodic_rank_connectivity_tests_with_141_ranks()
        run_triply_periodic_rank_connectivity_tests_with_114_ranks()
    end

    @testset "Local grids for distributed models" begin
        @info "  Testing local grids for distributed models..."
        run_triply_periodic_local_grid_tests_with_411_ranks()
        run_triply_periodic_local_grid_tests_with_141_ranks()
        run_triply_periodic_local_grid_tests_with_114_ranks()
    end

    @testset "Injection of halo communication BCs" begin
        @info "  Testing injection of halo communication BCs..."
        run_triply_periodic_bc_injection_tests_with_411_ranks()
        run_triply_periodic_bc_injection_tests_with_141_ranks()
        run_triply_periodic_bc_injection_tests_with_114_ranks()
    end

    # TODO: Larger halos!
    @testset "Halo communication" begin
        @info "  Testing halo communication..."
        run_triply_periodic_halo_communication_tests_with_411_ranks()
    end

    # TODO: 221 ranks
    # TODO: triply bounded
end

# MPI.Finalize()
# @test MPI.Finalized()
