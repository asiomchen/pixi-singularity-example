TAG ?= latest


build:
	docker build -t pixi-sif-example:${TAG} .

# this will fail due to https://github.com/sylabs/singularity/issues/4088
build-sif-docker:
	singularity build pixi-sif-example-${TAG}.sif docker-daemon:pixi-sif-example:${TAG}

# but saving the docker image to a tar file and then building the sif from that works
docker-save:
	docker save pixi-sif-example:${TAG} -o pixi-sif-example-${TAG}.tar

build-sif-from-tar:
	singularity build pixi-sif-example-${TAG}.sif docker-archive:pixi-sif-example-${TAG}.tar

run:
	docker run --rm -it pixi-sif-example:${TAG}

run-gpu:
	docker run --rm -it --gpus all pixi-sif-example:${TAG}

run-sif:
	singularity run pixi-sif-example-${TAG}.sif

run-sif-gpu:
	singularity run --nv pixi-sif-example-${TAG}.sif

# you might want to use exec instead of the run is some cases 
# https://github.com/apptainer/singularity/issues/3673
# but the enrtrypoint script is not called when using exec, so you might want to call it manually
exec-sif:
	singularity exec pixi-sif-example-${TAG}.sif test-openmm

history:
	docker history pixi-sif-example:${TAG}

ls:
	docker image ls pixi-sif-example:${TAG}
