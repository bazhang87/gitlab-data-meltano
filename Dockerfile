ARG MELTANO_IMAGE=meltano/meltano:v2.16.1-python3.8
FROM $MELTANO_IMAGE

WORKDIR /projects

# Install any additional requirements
COPY ./requirements.txt .
RUN pip install -r requirements.txt

# To fix the pg_config executable not found error
RUN apt-get update && \
    apt-get install libpq-dev -y && \
    apt-get clean;

# Install all plugins into the `.meltano` directory
COPY ./meltano.yml .
RUN meltano install
RUN meltano add orchestrator airflow
RUN cd orchestrate/dags && \
    rm meltano.py && \
    meltano upgrade files

# Add Java JDK for
RUN apt-get update && \
    apt-get install -y openjdk-11-jdk && \
    apt-get clean;

# Pin `discovery.yml` manifest by copying cached version to project root
RUN cp -n .meltano/cache/discovery.yml . 2>/dev/null || :

# Copy over remaining project files
COPY . .

# Expose default port used by `meltano ui`
EXPOSE 5000

ENTRYPOINT [ "meltano" ]
CMD [ "invoke", "airflow", "scheduler" ]