# Sandboxed execution environment for QuantumQuery
FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    r-base \
    r-base-dev \
    postgresql-client \
    mysql-client \
    sqlite3 \
    gcc \
    g++ \
    make \
    libpq-dev \
    libmysqlclient-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python data science packages
RUN pip install --no-cache-dir \
    pandas==2.1.4 \
    numpy==1.26.2 \
    scikit-learn==1.3.2 \
    matplotlib==3.8.2 \
    seaborn==0.13.0 \
    scipy==1.11.4 \
    statsmodels==0.14.1 \
    plotly==5.18.0 \
    sqlalchemy==2.0.23 \
    psycopg2-binary==2.9.9 \
    pymysql==1.1.0 \
    jupyter==1.0.0 \
    ipython==8.18.1

# Install R packages
RUN R -e "install.packages(c('tidyverse', 'ggplot2', 'dplyr', 'readr', 'DBI', 'RPostgreSQL', 'RMySQL'), repos='https://cloud.r-project.org/')"

# Create non-root user for security
RUN useradd -m -s /bin/bash sandbox && \
    mkdir -p /workspace /output && \
    chown -R sandbox:sandbox /workspace /output

# Set security restrictions
USER sandbox
WORKDIR /workspace

# Resource limits are set at runtime via Docker
CMD ["/bin/bash"]