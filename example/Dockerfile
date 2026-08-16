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

ENTRYPOINT [ "/app/entrypoint.sh" ]
CMD ["test-openmm"]
