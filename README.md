# Table of Contents

* [Preparing Meltano](#preparing-meltano)
  * [Xactly Setup](#xactly-setup)
  * [EdCast Setup](#edcast-setup)
  * [Meltano Setup](#meltano-setup)
  * [Running the Scheduler](#running-the-scheduler)
* [Preparing Meltano for Production](#preparing-meltano-for-production)
  * [Dockerize the Project](#dockerize-the-project)
  * [Google Cloud Platform Setup](#google-cloud-platform-setup)
    * [Admin SDK API :: Reports API](#admin-sdk-api---reports-api)
    * [Cloud SQL and Cloud SQL Admin](#cloud-sql-and-cloud-sql-admin)
    * [Container Registry](#container-registry)
      * [Kubernetes Engine](#kubernetes-engine)
      * [Install `kubectl` for Google Cloud SDK](#install-kubectl-for-google-cloud-sdk)
      * [Create a GKE Cluster](create-a-gke-cluster)
    * [Connect from GKE to Cloud SQL](#connect-from-gke-to-cloud-sql)
    * [Create Kubernetes Secrets](#create-kubernetes-secrets)
      * [Create Additional Secrets](#create-additional-secrets)
  * [Deploy Meltano to Kubernetes](#deploy-meltano-to-kubernetes)

# Preparing Meltano <a name="preparing-meltano"></a>

For more information how we use `Meltano` in GitLab, refer to [Meltano-Gitlab](https://about.gitlab.com/handbook/business-technology/data-team/platform/Meltano-Gitlab/) page.

Below is a guide on how to set up the Meltano project. Currently these are the taps/targets installed:

* [Tap Xactly](https://gitlab.com/gitlab-data/meltano_taps.git#subdirectory=tap-xactly)
* [Tap EdCast](https://gitlab.com/gitlab-data/meltano_taps.git#subdirectory=tap-edcast)
* [Target Snowflake](https://meltano.com/plugins/loaders/snowflake--meltano.html#snowflake-meltano-variant)

Setup of these taps/targets must be completed before the Meltano project is launched.

## Xactly Setup  <a name="xactly-setup"></a>
The only main concern with Xactly is the presence of the JDBC driver. In order to accomodate this, environment variables must be set correctly so that Meltano and the tap can access the Database correctly.

For Xactly specifically, the following variables MUST be set:

* `username`
* `password`
* `client_id`
* `consumer`

## EdCast Setup <a name="edcast-setup"></a>
The setup for `EdCast` is fairly simple. It consuming data from `RESTful API`. In order to accomodate this, environment variables must be set correctly so that Meltano and the tap can access the Database correctly.

For `EdCast` specifically, the following variables MUST be set:
* `start_date` - start date when want to load the data. Exposed in the [ISO date time format](https://en.wikipedia.org/wiki/ISO_8601#Time_offsets_from_UTC) `2000-01-01T00:00:00Z`
* `end_date` - end date when want to load the data. Exposed in the [ISO date time format](https://en.wikipedia.org/wiki/ISO_8601#Time_offsets_from_UTC) `2030-01-01T00:00:00Z`
* `username` - username for the acccess, got from the provider
* `password` - password for the acccess, got from the provider
* `url_base` - base `URL` address to access the API, usually it is `https://api.domo.com`


## Meltano Setup <a name="meltano-setup"></a>

The following sections must be changed in the `meltano.yml` file before installation:

* Under the `config` of `target-snowflake`, change `account`, `database`, `warehouse`, and `role` to your respective settings. For more information on the specific settings, read the [Meltano Snowflake documentation](https://meltano.com/plugins/loaders/snowflake--meltano.html)

Once the above settings are changed, run the following command to install your environment:

```bash
# Without Docker
meltano install

# With Docker
docker run -v $(pwd):/projects -w /projects meltano/meltano:latest-python3.8 install
```

In order for the installed Meltano taps to function properly, the following [environment varaiables](https://en.wikipedia.org/wiki/Environment_variable) must be set:

```bash
SF_USER="<USER>"
SF_PASSWORD="<PASSWORD>"

AIRFLOW__CORE__SQL_ALCHEMY_CONN="<postgresql://username:password@localhost:5432/mydatabase>"
AIRFLOW__CORE__DAGBAG_IMPORT_TIMEOUT="120"
AIRFLOW__CORE__EXECUTOR="LocalExecutor"
```

For local development, the easiest way to set these environment variables is to make a `.env` file with the necessary credentials in the root directory. The following environment variables can be ignored in the development environment:

* `AIRFLOW__CORE__SQL_ALCHEMY_CONN`
  * There is an internal SQLite database included with Meltano for development use
* `AIRFLOW__CORE__DAGBAG_IMPORT_TIMEOUT`
  * Import timeout is not an issue on local systems
* `AIRFLOW__CORE__EXECUTOR`
  * The default `SequentialExecutor` works with SQLite

Once installed and the environment variables have been set up, you may run any command from the [Meltano CLI](https://meltano.com/docs/command-line-interface.html)

## Running the Scheduler <a name="running-the-scheduler"></a>

Scheduling is handled with Meltano's built-in [Airflow](https://airflow.apache.org/). Currently, each tap is scheduled to sync every day. If you wish to change the frequency of individual syncs, you can change the value of `interval` under the `schedules` section within `meltano.yml`. Refer to the [Meltano documentation](https://meltano.com/docs/command-line-interface.html#how-to-use-7) for presets and valid intervals.

To run the scheduler, run the following command

```bash
# Without Docker
meltano invoke airflow scheduler

# With Docker
docker run -v $(pwd):/projects -w /projects meltano/meltano:latest-python3.8 invoke airflow scheduler
```

# Preparing a Production Environment for Meltano <a name="preparing-meltano-for-production"></a>

Below are the steps to get your Meltano project ready for a production environment. The production deployment instructions are for Google Cloud Platform using the Google Cloud SDK, and covers the following services:

* Container Registry
* Cloud SQL (Postgres)
* Kubernetes Engine

The deployment implements Kubernetes Secrets for sensative environment variables, as well as a .json key file that is used to authorize the Cloud SQL proxy in a Kubernetes sidecar setup.

## Dockerize the Project <a name="dockerize-the-project"></a>

Once the taps have been set up and the `meltano.yml` file has been changed, you can create a docker image to get ready for deployment to production. The provided `Dockerfile` will build the image and start up the Meltano Scheduler.

To build the image, run the following command in the root directory:

```bash
docker build --tag <IMAGE NAME>:<TAG NAME> .
```

Documentation for building containers with Docker can be found [here](https://docs.docker.com/engine/reference/commandline/build/).

## Google Cloud Platform Setup <a name="google-cloud-platform-setup"></a>

This section covers the necessary steps to create a GCP Production environment for the Meltano application. A GCP Project is a required, and it is reccomended that the [Google Cloud SDK](https://cloud.google.com/sdk/docs/quickstart) is installed in order to follow commands used in this guide. The following GCP APIs must be enabled:

* Admin SDK
* Kubernetes Engine
* Cloud SQL
* Cloud SQL Admin
* Container Registry
* Additional API dependencies will be created as necessary by the services listed above
  * This is typical behavior for GCP APIs

### Cloud SQL and Cloud SQL Admin <a name="cloud-sql-and-cloud-sql-admin"></a>

The Cloud SQL and Cloud SQL Admin APIs are used to store Airflow metadata in the Meltano production environment. The Cloud SQL Admin API is necessary in order to create a Cloud SQL Proxy within a Kubernetes [deployment](https://cloud.google.com/kubernetes-engine/docs/concepts/deployment).

Enable the Cloud SQL API

* [Cloud SQL API](https://console.cloud.google.com/apis/library/sql-component.googleapis.com).

Enable the Cloud SQL Admin API

* [Cloud SQL Admin API](https://console.cloud.google.com/apis/library/sqladmin.googleapis.com)

Create a Cloud SQL (PostgreSQL 12) instance if one does not already exist.

* [Cloud SQL + Postgres 12 Quickstart](https://cloud.google.com/sql/docs/postgres/quickstart)

There are some things to keep track of from this setup that will be needed to customize the Kubernetes deployment file `gitlab-app.yaml`:

* Cloud SQL instance name
* The connection name of the Cloud SQL instance
  * Example: `your-projectid-123456:region:instance-name`
* The name of the database where the Airflow metadata will be stored
  * The database name included in `gitlab-app.yaml` is `airflow-meta`
  * A user name for the database
    * The password of the user

### Container Registry <a name="container-registry"></a>

The Container Registry is used to store the Docker image that will be deployed in Kubernetes Engine. Artifact Registry can be used as an alternative, but the `gcloud sdk` commands in this guide will be for Container Registry.

Enable the Container Registry API

* [Google Container Registry API](https://console.cloud.google.com/apis/library/containerregistry.googleapis.com)

Container Registry will need to be authenticated in your local environment using the [Google Cloud SDK](https://cloud.google.com/sdk/docs/quickstart) to push and pull images. This can be ignored if Container Registry has been previously authenticated for other local projects.

* [Authenticate Docker for Google Cloud SDK](https://cloud.google.com/container-registry/docs/quickstart#auth)

Google Container Registry docs can be found [here](https://cloud.google.com/container-registry/docs/quickstart).

### Kubernetes Engine <a name="kubernetes-engine"></a>

Kubernetes Engine is used to deploy the production Meltano application. If there is an existing Kubernetes cluster that you would like to use for deploying Meltano skip the [Create a GKE Cluster](#create-a-gke-cluster) section.

Enable the Kubernetes Engine API

* [Kubernetes Engine](https://console.cloud.google.com/apis/library/container.googleapis.com)

Kubernetes docs can be found [here](https://kubernetes.io/docs/home/).

#### Install `kubectl` for Google Cloud SDK <a name="install-kubectl-for-google-cloud-sdk"></a>

https://cloud.google.com/kubernetes-engine/docs/quickstart#choosing_a_shell

Select `Local shell`, and then run the following command:

```bash
gcloud components install kubectl
```

#### Create a GKE Cluster <a name="create-a-gke-cluster"></a>

https://cloud.google.com/kubernetes-engine/docs/quickstart#create_cluster

```bash
gcloud container clusters create cluster-name --num-nodes=1
```

Authenticate the Cluster

```bash
gcloud container clusters get-credentials cluster-name
```

### Connect from GKE to Cloud SQL <a name="connect-from-gke-to-cloud-sql"></a>

The following guide section explains the process to create a service account key file and attach it to a Kubernetes secret, which will then be used by Cloud SQL Proxy for authentication:

https://cloud.google.com/sql/docs/postgres/connect-kubernetes-engine#service-account-key-file

* When creating Kubernetes secrets use the `--namespace=gitlab` flag

```bash
# Example

kubectl create secret generic <YOUR-DB-SECRET> --namespace=gitlab \
  --from-literal=username=<YOUR-DATABASE-USER> \
  --from-literal=password=<YOUR-DATABASE-PASSWORD> \
  --from-literal=database=<YOUR-DATABASE-NAME>
```

* Ensure that the service account you create (or use) has Cloud SQL Admin API IAM access with the Editor role
* The `key.json` created for the service account will be saved as a Kubernetes secret
  * The `key.json` file should be stored in a secure location in case it needs to be accessed in the future
* The `gitlab-app.yaml` file stores the value of `key.json` to the environment variable `ADMIN_SDK_KEY`
  * The Kubernetes secret name is `admin-sdk`
    * The key is `service_key`
      * The value associated with the above key is `key.json`

The Kubernetes secret name used in `gitlab-app.yaml` for the Cloud SQL credentials is:

* `airflow-db`
* The key names within `airflow-db` are:
  * `username`
    * The user name for the Cloud SQL database created in [this section of the guide](#cloud-sql-and-cloud-sql-admin)
  * `password`
    * The password for the Cloud SQL database user created in [this section of the guide](#cloud-sql-and-cloud-sql-admin)
  * `database`
    * The database name for the Cloud SQL database created in [this section of the guide](#cloud-sql-and-cloud-sql-admin)

The Cloud SQL Admin API should be enabled from [this section of the guide](#cloud-sql-and-cloud-sql-admin). If is not enabled, please proceed to [Connecting using the Cloud SQL Proxy](https://cloud.google.com/sql/docs/postgres/connect-kubernetes-engine#proxy) which explains why it is necessary to enable the Cloud SQL Admin API.

### Create Kubernetes Secrets <a name="create-kubernetes-secrets"></a>

Create the other necessary Kubernetes [secrets](https://cloud.google.com/kubernetes-engine/docs/concepts/secret). If the secret names and keys that are created match what is in the `gitlab-app.yaml` file it minimizes the edits required to customize the deployment.

All secrets must be created for the `gitlab` namespace

```bash
# Example

kubectl create secret generic my-secret-name --from-literal user=admin --namespace=gitlab
```

#### Create Additional Secrets <a name="create-additional-secrets"></a>

* Secret Name
  * `tap-secrets`
* Keys
  * `airflow_conn`
    * `postgresql://username:password@localhost:5432/mydatabase`
  * `sf_password`
    * Snowflake instance password
  * `sf_user`
    * Snowflake instance user name
  * `tap_xactly`
    * Xactly information related to JDBC login
* Secret Name
  * `admin-sdk`
* Keys
  * `service_key`
    * The service account key created during the [Gmail Setup](#gmail-setup)

## Deploy Meltano to Kubernetes <a name="deploy-meltano-to-kubernetes"></a>

To deploy to Kubernetes upload the Docker image to Container Registry.

**Step 1** - Tag the image:

```bash
docker tag img_name gcr.io/[PROJECT-ID]/img_name:tag
```

**Step 2** - Push the image to Google Container Registry:

```bash
docker push gcr.io/[PROJECT-ID]/img_name:tag1
```

The `gitlab-app.yaml` is used to create the Kubernetes deployment. To create a deployment on your Kubernetes cluster run:

`kubectl apply -f ./gitlab-app.yaml`

Update the `gitlab-app.yaml` file as necessary before deploying.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitlab-production  # Name of the deployment
  namespace: gitlab  # Namespace of the deployment
spec:
  replicas: 1  # We recommend 1 replica
  selector:
    matchLabels:
      app: gitlab
  template:
    metadata:
      labels:
        app: gitlab
    spec:
      serviceAccount: k8s-sa  # Replace with service account name created in the section 'Connect From GKE to Cloud SQL'
      serviceAccountName: k8s-sa  # Replace with service account created in the section 'Connect From GKE to Cloud SQL'
      containers:
      - name: gitlab
        image: gcr.io/<your-projectid-123456>/<image-name:image-tag>  #  The Gitlab-Meltano image
        imagePullPolicy: Always
        env:
        - name: DB_USER  # Cloud SQL Postgres user name
          valueFrom:
            secretKeyRef:
              name: airflow-db
              key: username
        - name: DB_PASS  # Cloud SQL Postgres password for user
          valueFrom:
            secretKeyRef:
              name: airflow-db
              key: password
        - name: DB_NAME  # Cloud SQL Postgres database anem
          valueFrom:
            secretKeyRef:
              name: airflow-db
              key: database
        - name: TAP_SLACK_TOKEN
          valueFrom:
            secretKeyRef:
              name: tap-secrets
              key: tap_slack_token
        - name: TAP_ZOOM_JWT
          valueFrom:
            secretKeyRef:
              name: tap-secrets
              key: tap_zoom_jwt
        - name: SF_USER
          valueFrom:
            secretKeyRef:
              name: tap-secrets
              key: sf_user
        - name: SF_PASSWORD
          valueFrom:
            secretKeyRef:
              name: tap-secrets
              key: sf_password
        - name: AIRFLOW__CORE__SQL_ALCHEMY_CONN
          valueFrom:
            secretKeyRef:
              name: tap-secrets
              key: airflow_conn
        - name: ADMIN_SDK_KEY
          valueFrom:
            secretKeyRef:
              name: admin-sdk
              key: service_key
        - name: AIRFLOW__CORE__DAGBAG_IMPORT_TIMEOUT  # Set environment variable
          value: "120"
        - name: AIRFLOW__CORE__EXECUTOR  # Set environment variable
          value: "LocalExecutor"
      - name: cloud-sql-proxy  # Cloud SQL Proxy Sidecar
        # It is recommended to use the latest version of the Cloud SQL proxy
        # Make sure to update on a regular schedule!
        image: gcr.io/cloudsql-docker/gce-proxy
        command:
          - "/cloud_sql_proxy"

          # If connecting from a VPC-native GKE cluster, you can use the
          # following flag to have the proxy connect over private IP
          # - "-ip_address_types=PRIVATE"

          # Replace DB_PORT with the port the proxy should listen on
          # Defaults: MySQL: 3306, Postgres: 5432, SQLServer: 1433
          # Copy and paste your SQL instance connection name into the code below
          - "-instances=<your-projectid-123456:zone:instance-name>=tcp:5432"

          # This flag specifies where the service account key can be found
          - "-credential_file=/secrets/service_account.json"  # The service account key for Cloud SQL Proxy
        securityContext:
          # The default Cloud SQL proxy image runs as the
          # "nonroot" user and group (uid: 65532) by default.
          runAsNonRoot: true
        volumeMounts:
        - name: k8s-sql-volume
          mountPath: /secrets/
          readOnly: true
      volumes:
      - name: k8s-sql-volume
        secret:
          secretName: cloud-sql  # The secret that contains service_account.json for Cloud SQL Proxy

```
