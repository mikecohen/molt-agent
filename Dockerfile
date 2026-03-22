# Multi-stage build for Cloud Run only (the agent refuses to start without K_SERVICE).
FROM golang:1.22-alpine AS build
WORKDIR /src

COPY go.mod ./
COPY . .
RUN go mod tidy && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /agent ./cmd/agent

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /agent /agent
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/agent"]
