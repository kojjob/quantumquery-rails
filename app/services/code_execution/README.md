# Code Execution System

A secure, sandboxed code execution environment for running user-generated analysis code in Python, R, and SQL. Built with Docker containers for isolation and security.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Analysis Request                          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              Code Validation (Security Check)                │
│  - Forbidden imports/functions                               │
│  - SQL injection detection                                   │
│  - File system access validation                             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  CodeExecutionJob (async)                    │
│  - Queued via Solid Queue                                    │
│  - Retry logic (3 attempts)                                  │
│  - Timeout handling                                          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              ExecutorFactory.build(language)                 │
└─────────────────────────────────────────────────────────────┘
                              │
            ┌─────────────────┼─────────────────┐
            │                 │                 │
            ▼                 ▼                 ▼
    ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
    │   Python     │  │      R       │  │     SQL      │
    │  Executor    │  │  Executor    │  │  Executor    │
    └──────────────┘  └──────────────┘  └──────────────┘
            │                 │                 │
            ▼                 ▼                 ▼
    ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
    │Docker        │  │Docker        │  │Direct DB     │
    │Container     │  │Container     │  │Connection    │
    │(isolated)    │  │(isolated)    │  │(read-only)   │
    └──────────────┘  └──────────────┘  └──────────────┘
```

## Security Model

### Container Isolation
- **Network Isolation**: Containers run on bridge network with no external access
- **Resource Limits**: 
  - Memory: 512MB max
  - CPU: 1 core max
  - Timeout: 60 seconds max
- **File System**: Read-only except `/workspace` mount
- **No Host Access**: Complete isolation from host system

### SQL Security
- **Read-Only User**: Separate database user with SELECT-only privileges
- **Query Timeout**: 30-second limit on query execution
- **Connection Pooling**: Managed connections prevent resource exhaustion
- **No DDL**: Data definition changes (CREATE, DROP, ALTER) blocked

### Code Validation
All code passes through validation before execution:
- **Python**: Forbidden imports (`os`, `subprocess`, `eval`), file operations
- **R**: System commands (`system`, `system2`), dangerous functions
- **SQL**: Injection patterns, DDL statements, multiple queries

## Language Support

### Python 3.11
**Image**: `quantumquery/python-executor:latest`

**Pre-installed Libraries**:
- Data Processing: pandas, numpy
- Machine Learning: scikit-learn
- Visualization: matplotlib, seaborn, plotly
- Statistics: scipy, statsmodels
- File I/O: openpyxl

**Data Access**:
```python
import pandas as pd

# Dataset injected as pickle file
df = pd.read_pickle('/workspace/data.pkl')

# Work with data
result = df.describe()

# Save plots
import matplotlib.pyplot as plt
plt.figure()
plt.plot(df['column'])
plt.savefig('/workspace/plots/output.png')

# Output results (JSON to stdout)
print(result.to_json())
```

### R 4.3.2
**Image**: `quantumquery/r-executor:latest`

**Pre-installed Packages**:
- Data Processing: tidyverse, data.table
- Visualization: ggplot2
- Machine Learning: caret, randomForest
- JSON: jsonlite

**Data Access**:
```r
library(tidyverse)

# Dataset injected as RDS file
data <- readRDS('/workspace/data.rds')

# Work with data
summary_stats <- summary(data)

# Save plots
ggplot(data, aes(x = column)) +
  geom_histogram() +
  ggsave('/workspace/plots/output.png')

# Output results (JSON to stdout)
library(jsonlite)
cat(toJSON(summary_stats))
```

### SQL
**Direct Database Connection** (no container)

**Supported Databases**:
- PostgreSQL
- MySQL
- MongoDB (via connection string)

**Usage**:
```sql
-- Read-only queries
SELECT column1, column2
FROM table_name
WHERE condition = 'value'
LIMIT 1000;
```

## Adding New Languages

To add support for a new language (e.g., Julia, JavaScript):

### 1. Create Dockerfile
```dockerfile
# docker/julia-executor.Dockerfile
FROM julia:1.9

# Install required packages
RUN julia -e 'using Pkg; Pkg.add(["DataFrames", "CSV", "Plots"])'

WORKDIR /workspace
CMD ["julia", "/workspace/script.jl"]
```

### 2. Build Executor Class
```ruby
# app/services/code_execution/julia_executor.rb
module CodeExecution
  class JuliaExecutor < BaseExecutor
    DOCKER_IMAGE = "quantumquery/julia-executor:latest"
    
    protected
    
    def prepare_code_file
      # Write Julia script to temp file
      file = Tempfile.new(["script", ".jl"])
      file.write(code)
      file.close
      file.path
    end
    
    def prepare_data
      # Convert dataset to CSV or Julia format
      return nil unless dataset
      
      file = Tempfile.new(["data", ".csv"])
      file.write(dataset.to_csv)
      file.close
      file.path
    end
    
    def parse_results(output)
      # Parse Julia output format
      JSON.parse(output)
    rescue JSON::ParserError
      { output: output }
    end
  end
end
```

### 3. Update Factory
```ruby
# app/services/code_execution/executor_factory.rb
def self.build(language, code, options = {})
  case language.to_sym
  when :julia
    JuliaExecutor.new(code, options)
  # ... existing cases
  end
end

def self.supported?(language)
  [:python, :r, :sql, :julia].include?(language.to_sym)
end
```

### 4. Build Docker Image
```bash
docker build -t quantumquery/julia-executor:latest -f docker/julia-executor.Dockerfile .
```

### 5. Add Validation
```ruby
# app/services/code_validation/julia_validator.rb
module CodeValidation
  class JuliaValidator < BaseValidator
    FORBIDDEN_FUNCTIONS = %w[
      run download rm mkdir
    ].freeze
    
    def validate
      check_forbidden_functions
      check_file_operations
    end
  end
end
```

## Docker Images

### Building Images
```bash
# Build Python executor
docker build -t quantumquery/python-executor:latest -f docker/python-executor.Dockerfile .

# Build R executor
docker build -t quantumquery/r-executor:latest -f docker/r-executor.Dockerfile .

# Build all images
rake docker:build:all
```

### Testing Images
```bash
# Test Python image
docker run --rm quantumquery/python-executor:latest python -c "import pandas; print(pandas.__version__)"

# Test R image
docker run --rm quantumquery/r-executor:latest R -e "library(tidyverse); packageVersion('tidyverse')"
```

## Background Job

Code execution runs asynchronously via `CodeExecutionJob`:

```ruby
# Queue execution
step = ExecutionStep.create!(
  analysis_request: request,
  language: :python,
  generated_code: code,
  status: :executing
)

CodeExecutionJob.perform_later(step)
```

### Retry Logic
- **Attempts**: 3 total attempts
- **Backoff**: Exponential (1s, 2s, 4s)
- **Failures**: Logged to `execution_step.error_message`

### Status Flow
```
pending → executing → completed
                   ↘ failed
                   ↘ timeout
```

## Error Handling

### Common Errors

**Container Creation Failed**
```ruby
# Error: Docker daemon not running
# Solution: Start Docker service

Docker.version  # Check Docker availability
```

**Timeout Exceeded**
```ruby
# Error: Container exceeded 60s timeout
# Solution: Optimize code or increase timeout

executor = PythonExecutor.new(code, timeout: 120)
```

**Memory Limit Exceeded**
```ruby
# Error: Container OOM killed
# Solution: Reduce dataset size or increase memory

executor = PythonExecutor.new(code, memory: 1024)  # 1GB
```

**Image Not Found**
```ruby
# Error: Docker image not found
# Solution: Build Docker images

rake docker:build:all
```

### Debugging

**Enable Verbose Logging**:
```ruby
# In executor
Rails.logger.debug("Container stdout: #{stdout}")
Rails.logger.debug("Container stderr: #{stderr}")
```

**Inspect Container**:
```ruby
# Get container ID from result metadata
container_id = result.metadata[:container_id]

# Check logs (if container still exists)
container = Docker::Container.get(container_id)
puts container.logs(stdout: true, stderr: true)
```

**Manual Execution**:
```bash
# Run code manually in container
docker run -it --rm \
  -v $(pwd)/test_code.py:/workspace/script.py \
  quantumquery/python-executor:latest \
  python /workspace/script.py
```

## Performance

### Benchmarks
- **Cold Start**: ~2-3 seconds (container creation)
- **Warm Execution**: ~100-500ms (running container)
- **Cleanup**: ~500ms (container removal)

### Optimization Tips
1. **Pre-pull Images**: Pull images during deployment
2. **Reuse Containers**: For same-user sequential executions
3. **Batch Execution**: Process multiple steps in one container
4. **Dataset Caching**: Cache prepared datasets to avoid re-serialization

## Testing

Run tests with Docker available:
```bash
rails test test/services/code_execution_test.rb
```

Skip Docker tests if unavailable:
```bash
# Tests automatically skip if Docker not available
docker --version || echo "Tests will skip Docker checks"
```

## Monitoring

### Metrics to Track
- Execution duration by language
- Container resource usage
- Timeout frequency
- Failure rate by error type
- Image pull latency

### Production Checklist
- [ ] Docker images built and tagged
- [ ] Docker daemon running and healthy
- [ ] Resource limits tested under load
- [ ] Error alerting configured
- [ ] Container cleanup verified
- [ ] Image registry accessible
- [ ] Retry logic tested
- [ ] Timeout values tuned

## Troubleshooting

### Container Won't Start
```bash
# Check Docker daemon
docker info

# Check image exists
docker images | grep quantumquery

# Check disk space
df -h

# Check memory available
free -m
```

### Execution Hangs
```bash
# List running containers
docker ps

# Check container logs
docker logs <container_id>

# Force stop container
docker stop -t 5 <container_id>
```

### High Resource Usage
```bash
# Check container stats
docker stats

# List all containers (including stopped)
docker ps -a

# Clean up stopped containers
docker container prune

# Clean up unused images
docker image prune -a
```

## References

- [docker-api gem](https://github.com/swipely/docker-api)
- [Docker Resource Limits](https://docs.docker.com/config/containers/resource_constraints/)
- [Python Data Science Stack](https://www.scipy.org/stackspec.html)
- [R Tidyverse](https://www.tidyverse.org/)
