# frozen_string_literal: true

namespace :docker do
  desc "Build all Docker executor images"
  task :build_all do
    images = [
      { name: "python-executor", file: "docker/python-executor.Dockerfile" },
      { name: "r-executor", file: "docker/r-executor.Dockerfile" }
    ]

    puts "Building Docker executor images...\n\n"

    images.each do |image|
      puts "Building quantumquery/#{image[:name]}..."
      
      cmd = "docker build -t quantumquery/#{image[:name]}:latest -f #{image[:file]} ."
      
      success = system(cmd)
      
      if success
        puts "✓ Successfully built quantumquery/#{image[:name]}\n\n"
      else
        puts "✗ Failed to build quantumquery/#{image[:name]}\n\n"
        exit 1
      end
    end

    puts "All images built successfully!"
    puts "\nVerify with: docker images | grep quantumquery"
  end

  desc "Build Python executor image"
  task :build_python do
    puts "Building Python executor image..."
    
    cmd = "docker build -t quantumquery/python-executor:latest -f docker/python-executor.Dockerfile ."
    
    if system(cmd)
      puts "✓ Successfully built quantumquery/python-executor"
    else
      puts "✗ Failed to build Python executor image"
      exit 1
    end
  end

  desc "Build R executor image"
  task :build_r do
    puts "Building R executor image..."
    
    cmd = "docker build -t quantumquery/r-executor:latest -f docker/r-executor.Dockerfile ."
    
    if system(cmd)
      puts "✓ Successfully built quantumquery/r-executor"
    else
      puts "✗ Failed to build R executor image"
      exit 1
    end
  end

  desc "Test Docker executor images"
  task :test do
    puts "Testing Docker executor images...\n\n"

    # Test Python image
    puts "Testing Python executor..."
    python_cmd = 'docker run --rm quantumquery/python-executor:latest python -c "import pandas; import numpy; print(\'Python OK\')"'
    
    if system(python_cmd)
      puts "✓ Python executor working\n\n"
    else
      puts "✗ Python executor test failed\n\n"
      exit 1
    end

    # Test R image
    puts "Testing R executor..."
    r_cmd = 'docker run --rm quantumquery/r-executor:latest R -e "library(tidyverse); cat(\'R OK\\n\')"'
    
    if system(r_cmd)
      puts "✓ R executor working\n\n"
    else
      puts "✗ R executor test failed\n\n"
      exit 1
    end

    puts "All executor images working correctly!"
  end

  desc "Clean up Docker executor images"
  task :clean do
    puts "Cleaning up Docker executor images..."
    
    images = ["quantumquery/python-executor", "quantumquery/r-executor"]
    
    images.each do |image|
      system("docker rmi #{image}:latest 2>/dev/null")
      puts "✓ Removed #{image}"
    end
    
    puts "\nCleanup complete!"
  end

  desc "Show Docker executor image info"
  task :info do
    puts "Docker Executor Images:\n\n"
    
    system("docker images | grep -E 'REPOSITORY|quantumquery'")
    
    puts "\n\nDocker Daemon Info:"
    system("docker info | grep -E 'Server Version|Operating System|Total Memory|CPUs'")
  end
end
