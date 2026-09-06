FROM golang:1.22-bookworm AS build
WORKDIR /src
COPY go.mod .
COPY main.go .
COPY templates/ ./templates/
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/har-telemetry .

FROM gcr.io/distroless/static-debian12
WORKDIR /app
COPY --from=build /out/har-telemetry /app/har-telemetry
ENV ADDR=:8080
ENV DATA_DIR=/data
EXPOSE 8080
VOLUME ["/data"]
ENTRYPOINT ["/app/har-telemetry"]
