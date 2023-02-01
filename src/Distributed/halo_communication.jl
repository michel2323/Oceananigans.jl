using KernelAbstractions: @kernel, @index, Event, MultiEvent
using OffsetArrays: OffsetArray
using Oceananigans.Fields: fill_send_buffers!, fill_recv_buffers!, reduced_dimensions, instantiated_location

import Oceananigans.Fields: tupled_fill_halo_regions!

using Oceananigans.BoundaryConditions:
    fill_halo_size,
    fill_halo_offset,
    permute_boundary_conditions,
    PBCT, HBCT

import Oceananigans.BoundaryConditions: 
    fill_halo_regions!, fill_first, fill_halo_event!,
    fill_west_halo!, fill_east_halo!, fill_south_halo!,
    fill_north_halo!, fill_bottom_halo!, fill_top_halo!,
    fill_west_and_east_halo!, 
    fill_south_and_north_halo!,
    fill_bottom_and_top_halo!

#####
##### MPI tags for halo communication BCs
#####

sides  = (:west, :east, :south, :north, :top, :bottom)
side_id = Dict(side => n for (n, side) in enumerate(sides))

opposite_side = Dict(
    :west => :east, :east => :west,
    :south => :north, :north => :south,
    :bottom => :top, :top => :bottom
)

# Define functions that return unique send and recv MPI tags for each side.
# It's an integer where
#   digit 1: the side
#   digits 2-4: the "from" rank
#   digits 5-7: the "to" rank

RANK_DIGITS = 3

for side in sides
    side_str = string(side)
    send_tag_fn_name = Symbol("$(side)_send_tag")
    recv_tag_fn_name = Symbol("$(side)_recv_tag")
    @eval begin
        function $send_tag_fn_name(local_rank, rank_to_send_to)
            from_digits = string(local_rank, pad=RANK_DIGITS)
            to_digits = string(rank_to_send_to, pad=RANK_DIGITS)
            side_digit = string(side_id[Symbol($side_str)])
            return parse(Int, from_digits * to_digits * side_digit)
        end

        function $recv_tag_fn_name(local_rank, rank_to_recv_from)
            from_digits = string(rank_to_recv_from, pad=RANK_DIGITS)
            to_digits = string(local_rank, pad=RANK_DIGITS)
            side_digit = string(side_id[opposite_side[Symbol($side_str)]])
            return parse(Int, from_digits * to_digits * side_digit)
        end
    end
end

#####
##### Filling halos for halo communication boundary conditions
#####

function tupled_fill_halo_regions!(full_fields, grid::DistributedGrid, args...; kwargs...) 
    for field in full_fields
        fill_halo_regions!(field, args...; kwargs...)
    end
end

function fill_halo_regions!(field::DistributedField, args...; kwargs...)
    reduced_dims = reduced_dimensions(field)

    return fill_halo_regions!(field.data,
                              field.boundary_conditions,
                              field.indices,
                              instantiated_location(field),
                              field.grid,
                              field.boundary_buffers,
                              args...;
                              reduced_dimensions = reduced_dims,
                              kwargs...)
end

# TODO: combination of communicating and other boundary conditions in one direction are not implemented yet!
function fill_halo_regions!(c::OffsetArray, bcs, indices, loc, grid::DistributedGrid, buffers, args...; kwargs...)
    arch       = architecture(grid)
    child_arch = child_architecture(arch)
    halo_tuple = permute_boundary_conditions(bcs)
    
    fill_send_buffers!(c, buffers, grid, child_arch)

    for task = 1:3
        barrier = device_event(child_arch)
        fill_halo_event!(task, halo_tuple, c, indices, loc, arch, barrier, grid, buffers, args...; kwargs...)
    end

    fill_recv_buffers!(c, buffers, grid, child_arch)    

    return nothing
end

function fill_halo_event!(task, halo_tuple, c, indices, loc, arch::MultiArch, barrier, grid::DistributedGrid, args...; kwargs...)
    fill_halo!  = halo_tuple[1][task]
    bc_left     = halo_tuple[2][task]
    bc_right    = halo_tuple[3][task]

    # Calculate size and offset of the fill_halo kernel
    size   = fill_halo_size(c, fill_halo!, indices, bc_left, loc, grid)
    offset = fill_halo_offset(size, fill_halo!, indices)

    event  = fill_halo!(c, bc_left, bc_right, size, offset, loc, arch, barrier, grid, args...; kwargs...)
    if event isa Event
        wait(device(child_architecture(arch)), event)
    else
        length(event) > 0 && MPI.Waitall!([event...])
    end
    return nothing
end

#####
##### fill_west_and_east_halo!   }
##### fill_south_and_north_halo! } for when both halos are communicative (Single communicating halos are to be implemented)
##### fill_bottom_and_top_halo!  }
#####

for (side, opposite_side, dir) in zip([:west, :south, :bottom], [:east, :north, :top], [1, 2, 3])
    fill_both_halo! = Symbol("fill_$(side)_and_$(opposite_side)_halo!")
    send_side_halo  = Symbol("send_$(side)_halo")
    send_opposite_side_halo = Symbol("send_$(opposite_side)_halo")
    recv_and_fill_side_halo! = Symbol("recv_and_fill_$(side)_halo!")
    recv_and_fill_opposite_side_halo! = Symbol("recv_and_fill_$(opposite_side)_halo!")

    @eval begin
        function $fill_both_halo!(c, bc_side::HBCT, bc_opposite_side::HBCT, size, offset, loc, arch::MultiArch, 
                                   barrier, grid::DistributedGrid, buffers, args...; kwargs...)

            @assert bc_side.condition.from == bc_opposite_side.condition.from  # Extra protection in case of bugs
            local_rank = bc_side.condition.from

            child_arch = child_architecture(arch)

            send_req1 = $send_side_halo(c, grid, child_arch, loc[$dir], local_rank, bc_side.condition.to, buffers)
            send_req2 = $send_opposite_side_halo(c, grid, child_arch, loc[$dir], local_rank, bc_opposite_side.condition.to, buffers)

            recv_req1 = $recv_and_fill_side_halo!(c, grid, child_arch, loc[$dir], local_rank, bc_side.condition.to, buffers)
            recv_req2 = $recv_and_fill_opposite_side_halo!(c, grid, child_arch, loc[$dir], local_rank, bc_opposite_side.condition.to, buffers)

            return send_req1, send_req2, recv_req1, recv_req2
        end
    end
end

#####
##### Sending halos
#####

for (side_idx, side) in enumerate(sides)
    side_str = string(side)
    send_side_halo = Symbol("send_$(side)_halo")
    underlying_side_boundary = Symbol("underlying_$(side)_boundary")
    side_send_tag = Symbol("$(side)_send_tag")

    @eval begin
        function $send_side_halo(c, grid, ::CPU, side_location, local_rank, rank_to_send_to, buffers)
            send_buffer = $underlying_side_boundary(c, grid, side_location)
            send_tag = $side_send_tag(local_rank, rank_to_send_to)

            @debug "Sending " * $side_str * " halo: local_rank=$local_rank, rank_to_send_to=$rank_to_send_to, send_tag=$send_tag"
            send_req = MPI.Isend(send_buffer, rank_to_send_to, send_tag, MPI.COMM_WORLD)

            return send_req
        end

        function $send_side_halo(c, grid, ::GPU, side_location, local_rank, rank_to_send_to, buffers)
            send_buffer = buffers[$side_idx].send
            
            send_tag = $side_send_tag(local_rank, rank_to_send_to)

            @debug "Sending " * $side_str * " halo: local_rank=$local_rank, rank_to_send_to=$rank_to_send_to, send_tag=$send_tag"
            send_req = MPI.Isend(send_buffer, rank_to_send_to, send_tag, MPI.COMM_WORLD)

            return send_req
        end
    end
end

#####
##### Receiving and filling halos (buffer is a view so it gets filled upon receive)
#####

for (side_idx, side) in enumerate(sides)
    side_str = string(side)
    recv_and_fill_side_halo! = Symbol("recv_and_fill_$(side)_halo!")
    underlying_side_halo = Symbol("underlying_$(side)_halo")
    side_recv_tag = Symbol("$(side)_recv_tag")

    @eval begin
        function $recv_and_fill_side_halo!(c, grid, ::CPU, side_location, local_rank, rank_to_recv_from, buffers)
            recv_buffer = $underlying_side_halo(c, grid, side_location)
            recv_tag = $side_recv_tag(local_rank, rank_to_recv_from)

            @debug "Receiving " * $side_str * " halo: local_rank=$local_rank, rank_to_recv_from=$rank_to_recv_from, recv_tag=$recv_tag"
            recv_req = MPI.Irecv!(recv_buffer, rank_to_recv_from, recv_tag, MPI.COMM_WORLD)

            return recv_req
        end
    end

    @eval begin
        function $recv_and_fill_side_halo!(c, grid, ::GPU, side_location, local_rank, rank_to_recv_from, buffers)
            recv_buffer = buffers[$side_idx].recv
        
            recv_tag = $side_recv_tag(local_rank, rank_to_recv_from)

            @debug "Receiving " * $side_str * " halo: local_rank=$local_rank, rank_to_recv_from=$rank_to_recv_from, recv_tag=$recv_tag"
            recv_req = MPI.Irecv!(recv_buffer, rank_to_recv_from, recv_tag, MPI.COMM_WORLD)

            return recv_req
        end
    end
end