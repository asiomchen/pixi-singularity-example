TAG ?= latest


build:
	docker build --platform linux/amd64 -t pixi-sif-example:${TAG} .

build-sif-docker:
	singularity build pixi-sif-example-${TAG}.sif docker-daemon:pixi-sif-example:${TAG}

run:
	docker run --rm -it pixi-sif-example:${TAG}

run-gpu:
	docker run --rm -it --gpus all pixi-sif-example:${TAG}

history:
	docker history pixi-sif-example:${TAG}

ls:
	docker image ls pixi-sif-example:${TAG}
