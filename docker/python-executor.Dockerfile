# Python 3.11 slim with data science libraries
FROM python:3.11-slim

# Set working directory
WORKDIR /workspace

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Install Python data science libraries
RUN pip install --no-cache-dir \
    pandas==2.1.4 \
    numpy==1.26.2 \
    scikit-learn==1.3.2 \
    matplotlib==3.8.2 \
    seaborn==0.13.0 \
    scipy==1.11.4 \
    statsmodels==0.14.1 \
    plotly==5.18.0 \
    openpyxl==3.1.2 \
    xlrd==2.0.1

# Create non-root user for execution
RUN useradd -m -u 1000 -s /bin/bash coderunner && \
    chown -R coderunner:coderunner /workspace

# Switch to non-root user
USER coderunner

# Set Python to run in unbuffered mode for real-time output
ENV PYTHONUNBUFFERED=1

# Default command
CMD ["/bin/bash"]
