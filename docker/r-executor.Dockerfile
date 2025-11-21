# R with tidyverse and data science packages
FROM r-base:4.3.2

# Set working directory
WORKDIR /workspace

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    && rm -rf /var/lib/apt/lists/*

# Install R packages (install individually for better error reporting)
RUN R -e "install.packages('tidyverse', repos='https://cloud.r-project.org/')" && \
    R -e "install.packages('data.table', repos='https://cloud.r-project.org/')" && \
    R -e "install.packages('caret', repos='https://cloud.r-project.org/')" && \
    R -e "install.packages('randomForest', repos='https://cloud.r-project.org/')" && \
    R -e "install.packages('glmnet', repos='https://cloud.r-project.org/')" && \
    R -e "install.packages('plotly', repos='https://cloud.r-project.org/')" && \
    R -e "install.packages('readxl', repos='https://cloud.r-project.org/')" && \
    R -e "install.packages('writexl', repos='https://cloud.r-project.org/')" && \
    R -e "install.packages('jsonlite', repos='https://cloud.r-project.org/')"

# Create non-root user for execution (use different UID to avoid conflicts)
RUN useradd -m -u 10000 -s /bin/bash coderunner && \
    chown -R coderunner:coderunner /workspace

# Switch to non-root user
USER coderunner

# Default command
CMD ["/bin/bash"]
