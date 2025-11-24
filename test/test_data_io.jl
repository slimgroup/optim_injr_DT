using DrWatson, Test
using JLD2
@quickactivate "optim_injr_DT"

# Test data I/O functions
@testset "Data I/O" begin
    @testset "Path construction" begin
        # Test datadir function from DrWatson
        geo_path = datadir("geo")
        @test isa(geo_path, String)
        @test occursin("geo", geo_path)
        
        state_path = datadir("state")
        @test isa(state_path, String)
        @test occursin("state", state_path)
    end
    
    @testset "File existence checks" begin
        # Test that data directories exist (if data is present)
        geo_dir = datadir("geo")
        if isdir(geo_dir)
            @test isdir(geo_dir)
        end
        
        state_dir = datadir("state")
        if isdir(state_dir)
            @test isdir(state_dir)
        end
    end
    
    @testset "JLD2 file operations" begin
        # Test JLD2 save/load with temporary file
        test_data = Dict(
            "test_array" => [1.0, 2.0, 3.0],
            "test_string" => "hello",
            "test_number" => 42.0
        )
        
        test_file = joinpath(projectdir(), "test_temp.jld2")
        
        try
            # Save test data
            JLD2.save(test_file, test_data)
            @test isfile(test_file)
            
            # Load test data
            loaded_data = JLD2.load(test_file)
            @test loaded_data["test_array"] == test_data["test_array"]
            @test loaded_data["test_string"] == test_data["test_string"]
            @test loaded_data["test_number"] == test_data["test_number"]
        finally
            # Clean up
            if isfile(test_file)
                rm(test_file)
            end
        end
    end
    
    @testset "Array operations" begin
        # Test array manipulation common in data processing
        arr = [1.0, 2.0, 3.0, 4.0, 5.0]
        
        # Test finding last nonzero
        arr_with_zeros = [1.0, 2.0, 3.0, 0.0, 0.0]
        last_nonzero_idx = findlast(!iszero, arr_with_zeros)
        @test last_nonzero_idx == 3
        @test arr_with_zeros[last_nonzero_idx] == 3.0
        
        # Test array slicing
        @test arr[1:3] == [1.0, 2.0, 3.0]
        @test arr[end-1:end] == [4.0, 5.0]
    end
end

