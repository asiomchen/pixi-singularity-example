# From Pixi to Singularity: Shipping a Reproducible Environment for HPC

Python packaging has improved significantly in recent years, and [Pixi](https://pixi.sh/) is a particularly useful addition. It is a fast package manager for the Conda ecosystem with first-class lockfile support, multiple environments, and task management.

On HPC systems, however, Pixi and Conda environments share one practical problem: they contain a lot of files. Cluster administrators often limit not only the amount of storage a user can consume, but also the number of files they can create. A single environment can consume a significant share of both quotas.

Containers are a natural way to package the environment, but Docker is usually not available on shared HPC compute nodes. Singularity gives us a useful bridge: build the application with familiar Docker tooling, then convert the image to the Singularity Image Format (SIF) used on the cluster.

Inspired by Pavel Zwerschke's article on [shipping Conda environments with Pixi](https://tech.quantco.com/blog/pixi-production), I tried this approach with a small project that runs the OpenMM installation test.

## Why Singularity?

Singularity is a container runtime designed with shared systems and HPC workloads in mind. A SIF image is usually a single, compressed, read-only file. Instead of storing every environment file separately on the cluster, we can package the entire environment as one portable artifact.

I deliberately use a Docker image as the starting point. Docker images are convenient to build locally, use in CI, and publish to a registry. The final SIF image is the artifact intended for the HPC system.

The workflow looks like this:

```text
pixi.lock
    -> Pixi production environment
    -> Docker image
    -> Singularity SIF image
    -> OpenMM on HPC
```

## The example project

The example lives in the [repository's](https://github.com/asiomchen/pixi-singularity-example) `example/` directory. Unless noted otherwise, run the commands below from that directory.

The project exposes a small `test-openmm` command that imports and runs OpenMM's built-in installation test. Its dependencies and environments are defined in `pixi.toml`:

```toml
[workspace]
name = "pixi-singularity-example"
channels = ["conda-forge"]
platforms = ["osx-arm64", "linux-64", "linux-aarch64", "win-64"]

[tasks]
start = "test-openmm"

[dependencies]
openmm = ">=8.0.0,<8.5.0"

[pypi-dependencies]
# This makes the script from our project available in the container.
my_project = { path = ".", editable = true }

[feature.dev.dependencies]
pytest = "*"
ruff = "*"
mypy = "*"

[feature.gpu.dependencies]
cuda-version = ">=12.0.0,<13.0.0"

[environments]
default = { features = ["dev", "gpu"], solve-group = "prod" }
cpu = { features = ["dev"], solve-group = "prod" }
prod = { features = ["gpu"], solve-group = "prod" }
```

Pixi lets us keep development and production dependencies in the same manifest. The `prod` environment contains the dependencies needed in the container, while the shared solve group keeps the environments compatible. The committed `pixi.lock` records the exact package resolution used for the build.

The project code consists of a single function in `__init__.py`. It runs OpenMM's installation test and prints a message when the test succeeds:

```python
def test_openmm():
    from openmm.testInstallation import main

    main()
    print("Welcome from OpenMM!")
```

The function is exposed as a command in `pyproject.toml`:

```toml
[project.scripts]
test-openmm = "my_project:test_openmm"
```

The corresponding task is defined in `pixi.toml`:

```toml
[tasks]
start = "test-openmm"
```

We can now run the command directly with `pixi run test-openmm` or invoke the task with `pixi run start`. For more information about Pixi, see the official [documentation](https://pixi.prefix.dev).

## Building a minimal runtime image

We could keep Pixi in the final image and launch the application with `pixi run`, but it is not needed at runtime. A multi-stage Docker build lets Pixi create the environment in a build stage, then copies only the result into the production stage:

```dockerfile
FROM ghcr.io/prefix-dev/pixi:latest AS build

WORKDIR /app
COPY . .
RUN pixi install --locked -e prod
RUN pixi shell-hook -e prod -s bash > /shell-hook
RUN echo "#!/bin/bash" > /app/entrypoint.sh
RUN cat /shell-hook >> /app/entrypoint.sh
RUN echo 'echo "custom entrypoint was called"' >> /app/entrypoint.sh
RUN echo 'exec "$@"' >> /app/entrypoint.sh

FROM ubuntu:latest AS production
WORKDIR /app
COPY --from=build /app/.pixi/envs/prod /app/.pixi/envs/prod
COPY --from=build --chmod=0755 /app/entrypoint.sh /app/entrypoint.sh
COPY ./my_project /app/my_project

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["test-openmm"]
```

Three details are important here.

First, `pixi install --locked -e prod` installs the production environment and fails if the lockfile is out of date. The build therefore uses the dependency versions recorded in `pixi.lock`.

Second, `pixi shell-hook` generates the shell commands needed to activate that environment. We append `exec "$@"` to the generated hook so that the entrypoint activates the environment and then replaces itself with the requested command.

Finally, the environment is copied to the same path in both stages.

The resulting runtime image contains the application and its environment, but not the Pixi executable or its package cache.

Build it with:

```sh
docker build -t pixi-sif-example:latest .
```

## Converting the Docker image to SIF

The original plan was to convert the image directly from the local Docker daemon:

```sh
singularity build pixi-sif-example-latest.sif docker-daemon:pixi-sif-example:latest
```

In my environment, however, this command failed:

```text
INFO:    Starting build...
INFO:    Fetching OCI image...
FATAL:   While performing build: conveyor failed to get: open /var/cache/singularity/cache/blob/blobs/sha256/7e1b2a748ff0f19973e3db9ab52469809b53320ae4d8cad5fc9c415e0d4c3731: no such file or directory
```

The failure matches a known SingularityCE issue involving images imported from the Docker daemon. See the [SingularityCE issue](https://github.com/sylabs/singularity/issues/4088) for more context.

Fortunately, a simple workaround exists: export the Docker image to an archive, then build the SIF image from that archive.

```sh
docker save pixi-sif-example:latest -o pixi-sif-example-latest.tar
singularity build pixi-sif-example-latest.sif docker-archive:pixi-sif-example-latest.tar
```

The tar archive is only an intermediate artifact. The resulting `pixi-sif-example-latest.sif` file is what we copy to and run on the HPC system.

## Running the SIF image

When Singularity converts an OCI image, it uses the Docker `ENTRYPOINT` and `CMD` to construct the container's runscript. Running the SIF image therefore calls our activation script and then the default `test-openmm` command:

```sh
singularity run pixi-sif-example-latest.sif
```

The output confirms that the custom entrypoint ran and that OpenMM can compute forces.

```text
custom entrypoint was called

OpenMM Version: 8.4

There are 2 Platforms available:

1 Reference - Successfully computed forces
2 CPU - Successfully computed forces

All differences are within tolerance.
Welcome from OpenMM!
```

## `singularity run` versus `singularity exec`

Sometimes we want to execute a specific program instead of using the container's default runscript. That is what `singularity exec` is for. There are also cases where [`run` and `exec` differ in argument handling](https://github.com/apptainer/singularity/issues/3673).

However, executing `test-openmm` directly fails:

```sh
singularity exec pixi-sif-example-latest.sif test-openmm
```

```text
FATAL:   "test-openmm": executable file not found in $PATH
```

Unlike `singularity run`, `singularity exec` does not invoke the runscript generated from the Docker entrypoint. Consequently, the Pixi environment has not been activated, and `test-openmm` is not on `PATH`.

We can activate the environment explicitly by passing the command through the entrypoint:

```sh
singularity exec pixi-sif-example-latest.sif /app/entrypoint.sh test-openmm
```

```text
custom entrypoint was called

OpenMM Version: 8.4
All differences are within tolerance.
Welcome from OpenMM!
```

This invocation is slightly awkward, but it gives us the behavior we need: activate the packaged Pixi environment, then execute an arbitrary command inside it.

## Running with an NVIDIA GPU

The `prod` environment includes the GPU feature, which constrains the CUDA version used when Pixi resolves the environment:

```toml
[feature.gpu.dependencies]
cuda-version = ">=12.0.0,<13.0.0"
```

On a machine with a compatible NVIDIA driver, Singularity can expose the host's NVIDIA devices and libraries with `--nv`:

```sh
singularity run --nv pixi-sif-example-latest.sif
```

The same option can be used with `singularity exec`. Without a compatible GPU and host driver, the installation test uses the other platforms available in the container, as in the CPU-only output above.

## Conclusion

Pixi gives us a fast, reproducible way to define the OpenMM (or any other conda package) environment, while the multi-stage Docker build keeps Pixi and its cache out of the runtime image. Converting that image to SIF packages the environment's many files as a single portable artifact suitable for an HPC filesystem.
